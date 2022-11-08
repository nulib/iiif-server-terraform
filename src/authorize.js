const isString = require("lodash.isstring");
const fetch = require("node-fetch");

const dcApiEndpoint = "${dc_api_endpoint}";
const allowedFrom = allowedFromRegexes("${allow_from}");

function allowedFromRegexes(str) {
  var configValues = isString(str) ? str.split(";") : [];
  var result = [];
  for (var re in configValues) {
    result.push(new RegExp(configValues[re]));
  }
  return result;
}

function isBlurred({ region, size }) {
  if (region !== "full") return false; // not a full frame request
  if (typeof size !== "string") return false; // size parameter not specified

  const match = size.match(/!(\d+)?,(\d+)?/);
  if (match === null) return false; // constrained height and width not specified
  const width = Number(match[1]);
  const height = Number(match[2]);
  if (width <= 5 || height <= 5) return true; // image constrained to <=5px in its largest dimension

  return false;
}

async function authorize(params, referer, cookie) {
  if (params.filename == "info.json") return true;
  if (isBlurred(params)) return true;

  for (var re in allowedFrom) {
    if (allowedFrom[re].test(referer)) return true;
  }

  const id = params.id.split("/").slice(-1)[0];

  return await getImageAuthorization(id, cookie);
}

async function getImageAuthorization(id, cookieHeader) {
  const opts = {
    headers: {
      cookie: cookieHeader,
    },
  };

  const response = await fetch(
    `$${dcApiEndpoint}/file-sets/$${id}/authorization`,
    opts
  );
  return response.status == 204;
}

module.exports = authorize;
