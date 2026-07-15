var catbox = require('@hapi/catbox-redis').Engine,
    sinon  = require('sinon'),
    cache  = {};
    expires = {};

sinon.stub(catbox.prototype, 'isReady', function() {
  var self = this;
  self.client = {
    get : function(key, cb) {
      process.nextTick(function() {
        cb(null, cache[key]);
      });
    },
    set : function(key, value, cb) {
      cache[key] = value;
      process.nextTick(cb);
    },
    del : function(key, cb) {
      delete cache[key];
      process.nextTick(cb);
    },
    expire : function(key, time, cb) {
      if (expires[key]) {
        clearTimeout(expires[key]);
      }

      expires[key] = setTimeout(function() {
        delete cache[key];
        delete expires[key];
      }, time*1000);

      process.nextTick(cb);
    }
  }
  return true;
});
