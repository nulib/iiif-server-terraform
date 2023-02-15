#!/usr/bin/env node
const AWS = require('aws-sdk');
const YAML = require('yaml');
const fetch = require('node-fetch');
const fs = require('fs');

const SAR = new AWS.ServerlessApplicationRepository();

const getApplicationTemplate = async (applicationId) => {
  let body;
  const localFile = `${__dirname}/local_template.yaml`;
  if (fs.existsSync(localFile)) {
    body = fs.readFileSync(localFile).toString();
  } else {
    const changeSet = await SAR.createCloudFormationTemplate({ApplicationId: applicationId}).promise();
    const response = await fetch(changeSet.TemplateUrl);
    body = await response.text();
  }
  return YAML.parse(body);
};

const updateTemplate = (template) => {
  const resourceFile = fs.readFileSync(`${__dirname}/resources.yaml`, {encoding: 'utf-8'});
  const resources = YAML.parse(resourceFile);
  template.Resources.CachingEndpoint.Properties.DistributionConfig.CacheBehaviors = (template.Resources.CachingEndpoint.Properties.DistributionConfig.CacheBehaviors || []).concat(resources.behaviors);
  template.Resources.CachingEndpoint.Properties.DistributionConfig.Origins = (template.Resources.CachingEndpoint.Properties.DistributionConfig.Origins || []).concat(resources.origins);
  return template;
};

const input = fs.readFileSync(0, 'utf-8');
const { applicationId } = JSON.parse(input);
console.warn(`Preparing template for ${applicationId}`);
getApplicationTemplate(applicationId).then((template) => {
  const newTemplate = updateTemplate(template);
  const yaml = YAML.stringify(newTemplate);

  fs.writeFileSync(1, JSON.stringify({ template: yaml }));
});

