var _             = require('underscore'),
    config        = require('config'),
    Boom          = require('@hapi/boom'),
    _request      = require('request'),
    crypto        = require('crypto'),
    jwt           = require('jsonwebtoken'),
    userUtil      = require('../util/user');

var microsoftOidcConfigCache = null;
var microsoftJwksCache = {};

function microsoftConfig() {
  return config.app &&
    config.app.auth &&
    config.app.auth.microsoft
      ? config.app.auth.microsoft
      : {};
}

function isMicrosoftConfigured() {
  var ms = microsoftConfig();

  return !!(
    ms.enabled &&
    ms.tenantId &&
    ms.clientID &&
    ms.clientSecret &&
    ms.callbackURL
  );
}

function microsoftBaseUrl() {
  return 'https://login.microsoftonline.com/' + encodeURIComponent(microsoftConfig().tenantId);
}

function microsoftIssuer() {
  return 'https://login.microsoftonline.com/' + microsoftConfig().tenantId + '/v2.0';
}

function randomToken() {
  return crypto.randomBytes(24).toString('hex');
}

function getAllowedDomains() {
  var ms = microsoftConfig();

  if (!ms.allowedDomains || !Array.isArray(ms.allowedDomains)) {
    return [];
  }

  return ms.allowedDomains
    .filter(function(domain) {
      return !!domain;
    })
    .map(function(domain) {
      return String(domain).toLowerCase();
    });
}

function getEmailDomain(email) {
  var parts = String(email || '').toLowerCase().split('@');
  return parts.length === 2 ? parts[1] : '';
}

function isAllowedDomain(email) {
  var allowedDomains = getAllowedDomains();

  if (!allowedDomains.length) {
    return true;
  }

  return allowedDomains.indexOf(getEmailDomain(email)) >= 0;
}

function asPemCertificate(x5c) {
  var cert = x5c.match(/.{1,64}/g).join('\n');
  return '-----BEGIN CERTIFICATE-----\n' + cert + '\n-----END CERTIFICATE-----\n';
}

function requestJson(options) {
  return new Promise(function(resolve, reject) {
    options.json = true;

    _request(options, function(err, response, body) {
      if (err) {
        return reject(err);
      }

      if (!response || response.statusCode < 200 || response.statusCode >= 300) {
        return reject(new Error('HTTP request failed with status ' + (response && response.statusCode) + ': ' + JSON.stringify(body)));
      }

      resolve(body);
    });
  });
}

function getMicrosoftOpenIdConfiguration() {
  if (microsoftOidcConfigCache) {
    return Promise.resolve(microsoftOidcConfigCache);
  }

  var metadataUrl = microsoftBaseUrl() + '/v2.0/.well-known/openid-configuration';

  return requestJson({
    method: 'GET',
    url: metadataUrl
  }).then(function(body) {
    microsoftOidcConfigCache = body;
    return body;
  });
}

function getMicrosoftSigningKey(jwksUri, kid) {
  if (microsoftJwksCache[kid]) {
    return Promise.resolve(microsoftJwksCache[kid]);
  }

  return requestJson({
    method: 'GET',
    url: jwksUri
  }).then(function(jwks) {
    if (!jwks || !jwks.keys || !Array.isArray(jwks.keys)) {
      throw new Error('Invalid JWKS response from Microsoft.');
    }

    var key = jwks.keys.find(function(candidate) {
      return candidate.kid === kid;
    });

    if (!key || !key.x5c || !key.x5c.length) {
      throw new Error('Unable to find matching Microsoft signing key.');
    }

    var pem = asPemCertificate(key.x5c[0]);
    microsoftJwksCache[kid] = pem;

    return pem;
  });
}

function verifyMicrosoftIdToken(idToken, expectedNonce) {
  var decoded = jwt.decode(idToken, { complete: true });

  if (!decoded || !decoded.header || !decoded.header.kid) {
    return Promise.reject(new Error('Invalid Microsoft ID token header.'));
  }

  return getMicrosoftOpenIdConfiguration()
    .then(function(oidcConfig) {
      return getMicrosoftSigningKey(oidcConfig.jwks_uri, decoded.header.kid);
    })
    .then(function(signingKey) {
      return new Promise(function(resolve, reject) {
        jwt.verify(idToken, signingKey, {
          audience: microsoftConfig().clientID,
          issuer: microsoftIssuer(),
          algorithms: ['RS256']
        }, function(err, claims) {
          if (err) {
            return reject(err);
          }

          if (!claims.tid || String(claims.tid).toLowerCase() !== String(microsoftConfig().tenantId).toLowerCase()) {
            return reject(new Error('Microsoft tenant ID validation failed.'));
          }

          if (expectedNonce && claims.nonce !== expectedNonce) {
            return reject(new Error('Microsoft nonce validation failed.'));
          }

          if (!claims.oid) {
            return reject(new Error('Microsoft ID token did not contain oid claim.'));
          }

          resolve(claims);
        });
      });
    });
}

function extractMicrosoftProfile(claims) {
  var email = (
    claims.email ||
    claims.preferred_username ||
    claims.upn ||
    ''
  ).toLowerCase();

  if (!email) {
    throw new Error('Microsoft account did not provide an email or UPN.');
  }

  if (!isAllowedDomain(email)) {
    throw new Error('Microsoft account domain is not authorised.');
  }

  return {
    oid: claims.oid,
    tid: claims.tid,
    email: email,
    upn: (claims.preferred_username || claims.upn || email).toLowerCase(),
    name: claims.name || email.split('@')[0]
  };
}

function findMicrosoftUser(profile) {
  var query = {
    email: profile.email,
    username: userUtil.generate_username(profile.email),
    'profiles.microsoft.oid': profile.oid
  };

  return new Promise(function(resolve, reject) {
    User.findByMultiple(query, function(err, user) {
      if (err) {
        return reject(err);
      }

      resolve(user);
    });
  });
}

function markProfilesModified(user) {
  if (user.markModified) {
    user.markModified('profiles');
  }
}

function linkMicrosoftProfile(user, profile) {
  var changed = false;

  if (!user.profiles) {
    user.profiles = {};
    changed = true;
  }

  if (!user.profiles.microsoft) {
    user.profiles.microsoft = {};
    changed = true;
  }

  ['oid', 'tid', 'email', 'upn', 'name'].forEach(function(key) {
    if (user.profiles.microsoft[key] !== profile[key]) {
      user.profiles.microsoft[key] = profile[key];
      changed = true;
    }
  });

  if (!user.verified) {
    user.verified = true;
    changed = true;
  }

  if (changed) {
    markProfilesModified(user);
    return user.save().then(function() {
      return user;
    });
  }

  return Promise.resolve(user);
}

function createMicrosoftUser(profile) {
  var user = new User();

  user.email = profile.email;
  user.fullname = profile.name || profile.email.split('@')[0];
  user.username = userUtil.generate_username(profile.email);
  user.source = 'microsoft';
  user.verified = true;
  user.profiles = {
    microsoft: {
      oid: profile.oid,
      tid: profile.tid,
      email: profile.email,
      upn: profile.upn,
      name: profile.name
    }
  };

  return user.save();
}

function completeLogin(request, user, provider, defaultRedirect) {
  var redirectTo = request.yar.get('next') || defaultRedirect || '/home';

  request.yar.clear('next');
  request.yar.set('loggedInWith', provider);
  request.yar.set('userId', user.id);
  request.user = user;

  return request.success({ redirectTo: redirectTo });
}

module.exports = {
  // Google OAuth - optional, only works if configured
  google : function(request, h) {
    if (!config.app.auth || !config.app.auth.google || !config.app.auth.google.clientID) {
      return request.fail({
        message: 'Google OAuth is not configured. Please set up Google OAuth credentials.'
      });
    }

    request.yar.flash('auth', 'Google', true);
    if (request.query.next) {
      request.yar.set('next', request.query.next);
    }

    var googleAuthUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
    var params = new URLSearchParams({
      client_id: config.app.auth.google.clientID,
      redirect_uri: config.app.auth.google.callbackURL,
      response_type: 'code',
      scope: 'profile email',
      access_type: 'online'
    });

    return request.success({ redirectTo: googleAuthUrl + '?' + params.toString() });
  },

  googleCallback : function(request, h) {
    if (!config.app.auth || !config.app.auth.google || !config.app.auth.google.clientID) {
      return request.fail({
        message: 'Google OAuth is not configured.'
      });
    }

    var code = request.query.code;
    if (!code) {
      return request.fail({ message: 'No authorization code received from Google.' });
    }

    return new Promise(function(resolve, reject) {
      _request.post({
        url: 'https://oauth2.googleapis.com/token',
        form: {
          code: code,
          client_id: config.app.auth.google.clientID,
          client_secret: config.app.auth.google.clientSecret,
          redirect_uri: config.app.auth.google.callbackURL,
          grant_type: 'authorization_code'
        },
        json: true
      }, function(err, response, body) {
        if (err || !body.access_token) {
          return reject(err || new Error('Failed to get access token'));
        }
        resolve(body.access_token);
      });
    })
    .then(function(accessToken) {
      return new Promise(function(resolve, reject) {
        _request.get({
          url: 'https://www.googleapis.com/oauth2/v2/userinfo',
          headers: { Authorization: 'Bearer ' + accessToken },
          json: true
        }, function(err, response, profile) {
          if (err || !profile.email) {
            return reject(err || new Error('Failed to get user profile'));
          }
          profile.accessToken = accessToken;
          resolve(profile);
        });
      });
    })
    .then(function(profile) {
      return new Promise(function(resolve, reject) {
        User.findByMultiple({
          email: profile.email,
          username: userUtil.generate_username(profile.email),
          'profiles.google.id': profile.id
        }, function(err, user) {
          if (err) reject(err);
          else resolve(user);
        });
      })
      .then(function(user) {
        var next = request.yar.get('next');
        var promises = [];
        var updateUser = false;

        request.yar.reset();

        if (next) {
          request.yar.set('next', next);
        }

        request.yar.set('loggedInWith', 'google');

        if (user) {
          request.yar.flash('requested', user.username);

          if (!user.avatar && profile.picture) {
            updateUser = true;
            user.avatar = profile.picture;
          }

          if (!user.profiles) {
            user.profiles = {};
          }

          if (!user.profiles.google) {
            updateUser = true;
            user.profiles.google = {
              id: profile.id,
              token: profile.accessToken
            };
          }

          if (updateUser) {
            markProfilesModified(user);
            promises.push(user.save());
          }

          return Promise.all(promises).then(function() {
            return user;
          });
        }
        else {
          user = new User();
          user.email = profile.email;
          user.fullname = profile.name || profile.email.split('@')[0];
          user.username = userUtil.generate_username(profile.email);
          request.yar.flash('requested', user.username);
          user.source = 'google';
          user.avatar = profile.picture;
          user.profiles = {
            google: {
              id: profile.id,
              token: profile.accessToken
            }
          };

          return user.save()
            .then(function(newUser) {
              if (!next) {
                request.yar.set('next', '/welcome');
              }

              request.yar.set('grantDemoTrinkets', true);
              request.yar.flash('userAccountCreated', JSON.stringify({
                provider: 'google',
                username: newUser.username,
                email: newUser.email
              }));

              return newUser;
            });
        }
      });
    })
    .then(function(user) {
      return completeLogin(request, user, 'google', '/home');
    })
    .catch(function(err) {
      log.error('Google OAuth error:', err);
      return request.fail({ message: 'Authentication failed. Please try again.' });
    });
  },

  microsoft : function(request, h) {
    if (!isMicrosoftConfigured()) {
      return request.fail({
        message: 'Microsoft sign-in is not configured.'
      });
    }

    var state = randomToken();
    var nonce = randomToken();

    request.yar.flash('auth', 'Microsoft', true);
    request.yar.set('microsoftAuthState', state);
    request.yar.set('microsoftAuthNonce', nonce);

    if (request.query.next) {
      request.yar.set('next', request.query.next);
    }

    var authorizeUrl = microsoftBaseUrl() + '/oauth2/v2.0/authorize';
    var params = new URLSearchParams({
      client_id: microsoftConfig().clientID,
      response_type: 'code',
      redirect_uri: microsoftConfig().callbackURL,
      response_mode: 'query',
      scope: 'openid profile email',
      state: state,
      nonce: nonce
    });

    return request.success({ redirectTo: authorizeUrl + '?' + params.toString() });
  },

  microsoftCallback : function(request, h) {
    if (!isMicrosoftConfigured()) {
      return request.fail({
        message: 'Microsoft sign-in is not configured.'
      });
    }

    if (request.query.error) {
      return request.fail({
        message: request.query.error_description || request.query.error
      });
    }

    var code = request.query.code;
    var returnedState = request.query.state;
    var expectedState = request.yar.get('microsoftAuthState');
    var expectedNonce = request.yar.get('microsoftAuthNonce');
    var next = request.yar.get('next');

    request.yar.clear('microsoftAuthState');
    request.yar.clear('microsoftAuthNonce');

    if (!code) {
      return request.fail({ message: 'No authorization code received from Microsoft.' });
    }

    if (!expectedState || returnedState !== expectedState) {
      return request.fail({ message: 'Microsoft sign-in state validation failed.' });
    }

    return requestJson({
      method: 'POST',
      url: microsoftBaseUrl() + '/oauth2/v2.0/token',
      form: {
        client_id: microsoftConfig().clientID,
        client_secret: microsoftConfig().clientSecret,
        code: code,
        redirect_uri: microsoftConfig().callbackURL,
        grant_type: 'authorization_code'
      }
    })
    .then(function(tokenResponse) {
      if (!tokenResponse || !tokenResponse.id_token) {
        throw new Error('Microsoft token response did not contain an ID token.');
      }

      return verifyMicrosoftIdToken(tokenResponse.id_token, expectedNonce);
    })
    .then(function(claims) {
      return extractMicrosoftProfile(claims);
    })
    .then(function(profile) {
      return findMicrosoftUser(profile)
        .then(function(user) {
          var autoCreateUsers = microsoftConfig().autoCreateUsers !== false;

          request.yar.reset();

          if (next) {
            request.yar.set('next', next);
          }

          request.yar.set('loggedInWith', 'microsoft');

          if (user) {
            if (user.hasRole && user.hasRole('disabled')) {
              throw new Error('Account Disabled');
            }

            request.yar.flash('requested', user.username);
            return linkMicrosoftProfile(user, profile);
          }

          if (!autoCreateUsers) {
            throw new Error('No Trinket account exists for this Microsoft account.');
          }

          return createMicrosoftUser(profile)
            .then(function(newUser) {
              if (!next) {
                request.yar.set('next', '/welcome');
              }

              request.yar.set('grantDemoTrinkets', true);
              request.yar.flash('requested', newUser.username);
              request.yar.flash('userAccountCreated', JSON.stringify({
                provider: 'microsoft',
                username: newUser.username,
                email: newUser.email
              }));

              return newUser;
            });
        });
    })
    .then(function(user) {
      return completeLogin(request, user, 'microsoft', '/home');
    })
    .catch(function(err) {
      log.error('Microsoft OAuth error:', err);
      return request.fail({
        message: 'Microsoft sign-in failed. Please contact support if this continues.'
      });
    });
  }
};
