const authorize = require("./authorize");
const tiffBucket = "${tiff_bucket}";

function getEventHeader(request, name) {
  if (
    request.headers &&
    request.headers[name] &&
    request.headers[name].length > 0
  ) {
    return request.headers[name][0].value;
  } else {
    return undefined;
  }
}

function addAccessControlHeaders(request, response) {
  const origin = getEventHeader(request, "origin") || "*";
  if (!response.headers) response.headers = {};
  response.headers["access-control-allow-origin"] = [
    { key: "Access-Control-Allow-Origin", value: origin },
  ];
  response.headers["access-control-allow-headers"] = [
    { key: "Access-Control-Allow-Headers", value: "authorization, cookie" },
  ];
  response.headers["access-control-allow-credentials"] = [
    { key: "Access-Control-Allow-Credentials", value: "true" },
  ];
  return response;
}

function viewerRequestOptions(request) {
  const response = {
    status: "200",
    statusDescription: "OK",
    headers: {},
    body: "OK",
  };

  return addAccessControlHeaders(request, response);
}

function parsePath(path) {
  const segments = path.split(/\//).reverse();

  if (segments.length < 8) {
    return {
      poster: segments[2] == "posters",
      id: segments[1],
      filename: segments[0],
    };
  } else {
    return {
      poster: segments[5] == "posters",
      id: segments[4],
      region: segments[3],
      size: segments[2],
      rotation: segments[1],
      filename: segments[0],
    };
  }
}

async function viewerRequestIiif(request) {
  const path = decodeURI(request.uri.replace(/%2f/gi, ""));
  const params = parsePath(path);
  const referer = getEventHeader(request, "referer");
  const cookie = getEventHeader(request, "cookie");
  const authed = await authorize(params, referer, cookie, request.clientIp);
  console.log("Authorized:", authed);

  // Return a 403 response if not authorized to view the requested item
  if (!authed) {
    const response = {
      status: "403",
      statusDescription: "Forbidden",
      body: "Forbidden",
    };
    return addAccessControlHeaders(request, response);
  }

  // Set the x-preflight-location request header to the location of the requested item
  const pairtree = params.id.match(/.{1,2}/g).join("/");
  const s3Location = params.poster
    ? `s3://$${tiffBucket}/posters/$${pairtree}-poster.tif`
    : `s3://$${tiffBucket}/$${pairtree}-pyramid.tif`;
  request.headers["x-preflight-location"] = [
    { key: "X-Preflight-Location", value: s3Location },
  ];
  return request;
}

async function processViewerRequest(event) {
  console.log("Initiating viewer-request trigger");
  const { request } = event.Records[0].cf;
  let result;

  if (request.method === "OPTIONS") {
    // Intercept OPTIONS request and return proper response
    result = viewerRequestOptions(request);
  } else {
    result = await viewerRequestIiif(request);
  }

  return result;
}

async function processViewerResponse(event) {
  console.log("Initiating viewer-response trigger");
  const { request, response } = event.Records[0].cf;
  return addAccessControlHeaders(request, response);
}

async function processRequest(event, _context, callback) {
  const { eventType } = event.Records[0].cf.config;
  let result;

  console.log("Event Type:", eventType);
  if (eventType === "viewer-request") {
    result = await processViewerRequest(event);
  } else if (eventType === "viewer-response") {
    result = await processViewerResponse(event);
  } else {
    result = event.Records[0].cf.request;
  }

  return callback(null, result);
}

module.exports = { handler: processRequest };
