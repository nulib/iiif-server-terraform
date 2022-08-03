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

function getBearerToken(request) {
  let authHeader = getEventHeader(request, 'authorization');
  if (isString(authHeader)) {
    return authHeader.replace(/^Bearer /,'');
  }
  return null;
}

function getCookieToken(request) {
  let cookieHeader = getEventHeader(request, 'cookie');
  if (isString(cookieHeader)) {
    let cookies = cookie.parse(cookieHeader);
    if (isObject(cookies) && isString(cookies.IIIFAuthToken)) {
      return cookies.IIIFAuthToken;
    }
  }
  return null;
}

function getAuthToken(request) {
  return getBearerToken(request) || getCookieToken(request);
}

function addAccessControlHeaders(request, response) {
  const origin = getEventHeader(request, 'origin') || '*';
  response.headers['access-control-allow-origin'] = [{ key: 'Access-Control-Allow-Origin', value: origin }];
  response.headers['access-control-allow-headers'] = [{ key: 'Access-Control-Allow-Headers', value: 'authorization, cookie' }];
  response.headers['access-control-allow-credentials'] = [{ key: 'Access-Control-Allow-Credentials', value: 'true' }];
  return response;
}

function viewerRequestOptions(request) {
  const response = {
    status: '200',
    statusDescription: 'OK',
    headers: {},
    body: 'OK'
  };

  return addAccessControlHeaders(request, response);
}

function viewerRequestLogin(request) {
  const authToken = getAuthToken(request);
  const headers = {};
  if (authToken !== getCookieToken(request)) {
    const newCookieToken = authToken;
    const cookieOptions = { domain: '${auth_domain}' };
    if (authToken === '') {
      newCookieToken = 'deleted';
      cookieOptions.maxAge = -1;
    }
    headers['set-cookie'] = [{ 
      key: 'Set-Cookie', 
      value: cookie.serialize('IIIFAuthToken', newCookieToken, cookieOptions)
    }]
  }

  return {
    status: '200',
    statusDescription: 'OK',
    headers: headers,
    body: 'OK'
  };
}

function parsePath(path) {
  const segments = path.split(/\//).reverse();

  if (segments.length < 8) {
    return {
      poster: segments[2] == "posters",
      id: segments[1],
      filename: segments[0],
    }
  } else {
    return {
      poster: segments[5] == "posters",
      id: segments[4],
      region: segments[3],
      size: segments[2],
      rotation: segments[1],
      filename: segments[0],
    }
  }
}

async function viewerRequestIiif(request) {
  const path = decodeURI(request.uri.replace(/%2f/gi, ''));
  const authToken = getAuthToken(request);
  const params = parsePath(path);
  const referer = getEventHeader(request, 'referer');
  const authed = await authorize(authToken, params, referer);
  console.log('Authorized:', authed);

  // Return a 403 response if not authorized to view the requested item
  if (!authed) {
    const response = {
      status: '403',
      statusDescription: 'Forbidden',
      body: 'Forbidden'
    };
    return response;
  }

  // Set the x-preflight-location request header to the location of the requested item
  const pairtree = id.match(/.{1,2}/g).join('/');
  const s3Location = params.poster ? `s3://$${tiffBucket}/posters/$${pairtree}-poster.tif` : `s3://$${tiffBucket}/$${pairtree}-pyramid.tif`;
  request.headers['x-preflight-location'] = [{ key: 'X-Preflight-Location', value: s3Location }];
  return request;
}

async function processViewerRequest(event) {
  console.log('Initiating viewer-request trigger')
  const { request } = event.Records[0].cf;
  let result;

  if (request.method === 'OPTIONS') {
    // Intercept OPTIONS request and return proper response
    result = viewerRequestOptions(request);
  } else if (request.uri === '/iiif/login') {
    // Intercept login request and return new Set-Cookie response
    result = viewerRequestLogin(request);
  } else {
    result = await viewerRequestIiif(request);
  }

  return result;
}

async function processViewerResponse(event) {
  console.log('Initiating viewer-response trigger')
  const { request, response } = event.Records[0].cf;
  return addAccessControlHeaders(request, response);
}

async function processRequest(event, _context, callback) {
  const { eventType } = event.Records[0].cf.config;
  let result;

  console.log('Event Type:', eventType);
  if (eventType === 'viewer-request') {
    result = await processViewerRequest(event);
  } else if (eventType === 'viewer-response') {
    result = await processViewerResponse(event);
  } else {
    result = event.Records[0].cf.request;
  }

  return callback(null, result);
}

module.exports = { handler: processRequest };