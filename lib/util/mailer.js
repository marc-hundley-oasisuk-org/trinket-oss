var nodemailer = require('nodemailer'),
    config     = require('config'),
    _          = require('underscore');

// Check if email is properly configured
function isConfigured() {
  var mailConfig = config.app.mail;
  return mailConfig && mailConfig.from && mailConfig.host;
}

// Create reusable transporter
function createTransport() {
  var mailConfig = config.app.mail;
  var transportOptions = {
    host: mailConfig.host,
    port: mailConfig.port || 587,
    secure: mailConfig.secure || false,
    disableFileAccess: true,
    disableUrlAccess: true
  };

  if (mailConfig.user && mailConfig.pass) {
    transportOptions.auth = {
      user: mailConfig.user,
      pass: mailConfig.pass
    };
  }

  if (mailConfig.tls) {
    transportOptions.tls = mailConfig.tls;
  }

  return nodemailer.createTransport(transportOptions);
}


module.exports = {
  isConfigured: isConfigured,

  send: async function(to, subject, options) {
    if (!isConfigured()) {
      console.log('Email not configured, skipping send to:', to);
      return { skipped: true, reason: 'Email not configured' };
    }

    options = _.extend({
      from: config.app.mail.from,
      to: to,
      subject: subject
    }, options || {});

    var transport = createTransport();

    return new Promise(function(resolve, reject) {
      transport.sendMail(options, function(err, response) {
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }
};
