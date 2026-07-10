var httpClient = require('./http-client')
  , config     = require('config');

module.exports = {
  verify : function(g_recaptcha_response, cb) {
    // Skip recaptcha verification in test mode or if not configured
    if (config.isTest || !config.app.recaptcha || !config.app.recaptcha.secretkey) {
      return cb({ success : true });
    }

    httpClient.postFormJson("https://www.google.com/recaptcha/api/siteverify", {
        secret   : config.app.recaptcha.secretkey
      , response : g_recaptcha_response
    })
    .then(function(body) {
      cb(body);
    })
    .catch(function() {
      cb({ status : false });
    });
  }
};
