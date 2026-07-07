var undiciRequest = require('undici').request
  , fs             = require('fs')
  , pipeline       = require('util').promisify(require('stream').pipeline);

function buildRequestOptions(options) {
  var headers = Object.assign({}, options.headers || {});
  var method = options.method || (options.form ? 'POST' : 'GET');
  var body;

  if (options.form) {
    body = new URLSearchParams(options.form).toString();
    headers['content-type'] = headers['content-type'] || 'application/x-www-form-urlencoded';
  }
  else if (options.body) {
    body = options.body;
  }

  return {
    method: method,
    headers: headers,
    body: body,
    bodyTimeout: options.bodyTimeout || 30000,
    headersTimeout: options.headersTimeout || 30000
  };
}

function requestJson(options) {
  return undiciRequest(options.url, buildRequestOptions(options))
    .then(function(response) {
      return response.body.text()
        .then(function(text) {
          var body = text ? JSON.parse(text) : null;

          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw new Error('HTTP request failed with status ' + response.statusCode + ': ' + JSON.stringify(body));
          }

          return body;
        });
    });
}

function getJson(url, headers) {
  return requestJson({
    url: url,
    method: 'GET',
    headers: headers || {}
  });
}

function postFormJson(url, form, headers) {
  return requestJson({
    url: url,
    method: 'POST',
    form: form,
    headers: headers || {}
  });
}

function streamToFile(url, targetPath, onResponse) {
  return undiciRequest(url, {
    method: 'GET',
    bodyTimeout: 30000,
    headersTimeout: 30000
  })
  .then(function(response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return response.body.text()
        .then(function(text) {
          throw new Error('HTTP request failed with status ' + response.statusCode + ': ' + text);
        });
    }

    if (onResponse) {
      onResponse(response);
    }

    return pipeline(response.body, fs.createWriteStream(targetPath));
  });
}

module.exports = {
  requestJson  : requestJson,
  getJson      : getJson,
  postFormJson : postFormJson,
  streamToFile : streamToFile
};
