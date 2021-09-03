const isObject = require('lodash.isobject');
const isString = require('lodash.isstring');
const jwt      = require('jsonwebtoken');
const URI      = require('uri-js');
const AWS      = require('aws-sdk');

const apiTokenSecret = '${api_token_secret}';
const elasticSearch  = '${elastic_search}';
const allowedFrom    = allowedFromRegexes('${allow_from}');

function allowedFromRegexes(str) {
  var configValues = isString(str) ? str.split(';') : [];
  var result = [];
  for (var re in configValues) {
    result.push(new RegExp(configValues[re]));
  }
  return result;
}

function getCurrentUser(token) {
  if (isString(token)) {
    try {
      return jwt.verify(token, apiTokenSecret);
    } catch(err) {
      return null;
    }
  } else {
    return null;
  }
}

async function fetchJson(request) {
  return new Promise((resolve, _reject) => {
    var client = new AWS.HttpClient();
    client.handleRequest(request, null, (response) => {
      var responseBody = '';
      response.on('data', (chunk) => { 
        responseBody += chunk; 
      });
      response.on('end', () => { 
        response.body = responseBody;
        response.json = JSON.parse(responseBody);
        resolve(response);
      });
    }, (error) => {
      console.log("ERROR RETRIEVING AUTH DOCUMENT: ", error);
      resolve(null);
    });
  });
}

async function makeRequest(method, requestUrl, body = null) {
  return new Promise((resolve, reject) => {
    const region = elasticSearch.match(/\.([a-z]{2}-[a-z]+-\d)\./).slice(-1).toString();
    const chain = new AWS.CredentialProviderChain();
    const request = new AWS.HttpRequest(requestUrl, region);
    request.method = method;
    request.headers['Host'] = URI.parse(requestUrl).host;
    request.body = body;
    request.headers['Content-Type'] = 'application/json';

    chain.resolve((err, credentials) => { 
      if (err) {
        console.log('WARNING: ', err);
        console.log('Returning unsigned request');
      } else {
        var signer = new AWS.Signers.V4(request, 'es');
        signer.addAuthorization(credentials, new Date());
      }
      resolve(request);
    });
  });
}

async function authorize(token, id, referer) {
  for (var re in allowedFrom) {
    if (allowedFrom[re].test(referer)) return true;
  }

  id = id.split("/").slice(-1)[0]

  const currentUser = getCurrentUser(token);
  const doc = await getDoc(id);
  const visibility = getVisibility(doc._source);
  const username = isObject(currentUser) ? currentUser.displayName[0] : 'Anonymous';

  console.log('User:', username);
  console.log('Item ID:', id);
  console.log('Visibility:', visibility);

  switch(visibility) {
    case 'open':          return true;
    case 'authenticated': return isObject(currentUser);
    case 'restricted':    return false;
    default:              return true;
  }
}

async function getDoc(id) {
  var response = await getDocFromIndex(id, 'meadow');
  if (response.statusCode == 200) {
    return response.json;
  }
  response = await getDocFromIndex(id, 'common');
  return response.json
}

async function getDocFromIndex(id, index) {
  var docUrl = URI.resolve(elasticSearch, [index, '_doc', id].join('/'));
  var request = await makeRequest('GET', docUrl);
  return await fetchJson(request);
}

function getVisibility(source) {
  if (!isObject(source)) return null;

  if (isObject(source.visibility)) {
    return source.visibility.id.toLowerCase();
  } else if (isString(source.visibility)) {
    return source.visibility.toLowerCase();
  }

  return null;
}

module.exports = authorize;