const AWS        = require('aws-sdk');
const authorize  = require('./authorize');
const cookie     = require('cookie');
const isObject   = require('lodash.isobject');
const isString   = require('lodash.isstring');
const tiffBucket = '${tiff_bucket}';

function getEventHeader(request, name) {
  if (request.headers && request.headers[name] && request.headers[name].length > 0) {
    return request.headers[name][0].value;
  } else {
    return undefined;
  }
}

function getAuthToken(request) {
  let authHeader = getEventHeader(request, 'authorization');
  if (isString(authHeader)) {
    return authHeader.replace(/^Bearer /,'');
  }
  
  let cookieHeader = getEventHeader(request, 'cookie');
  if (isString(cookieHeader)) {
    let cookies = cookie.parse(cookieHeader);
    if (isObject(cookies) && isString(cookies.IIIFAuthToken)) {
      return cookies.IIIFAuthToken;
    }
  }

  return null;
}

async function processRequest(event, _context, callback) {
  const request = event.Records[0].cf.request;
  const path = decodeURI(request.uri.replace(/%2f/gi, ''));
  const [poster, id] = path.match(/^\/iiif\/2\/(posters\/)?([^/]+)/).slice(-2);
  const authToken = getAuthToken(request);
  const referer = getEventHeader(request, 'referer');
  
  const authed = await authorize(authToken, id, referer);
  console.log('Authorized:', authed);

  if (!authed) {
    const response = {
      status: '403',
      statusDescription: 'Forbidden',
      body: 'Forbidden'
    };
    return callback(null, response);
  }

  const pairtree = id.match(/.{1,2}/g).join('/');
  const s3Location = poster ? `s3://$${tiffBucket}/posters/$${pairtree}-poster.tif` : `s3://$${tiffBucket}/$${pairtree}-pyramid.tif`;
  request.headers['x-preflight-location'] = [{ key: 'X-Preflight-Location', value: s3Location }];
  return callback(null, request);
}

module.exports = { handler: processRequest };