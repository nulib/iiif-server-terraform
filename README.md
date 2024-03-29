![terraform style](https://github.com/nulib/iiif-server-terraform/actions/workflows/tflint.yml/badge.svg)

## Description

This terraform project includes the resources required to install and configure the IIIF Server.

## Prerequisites

- [core](https://github.com/nulib/infrastructure/blob/main/core/README.md)
- [data_services](https://github.com/nulib/infrastructure/blob/main/data_services/README.md)

## Setup

```
cd scripts && npm install && cd -
```

## Variables

- `aliases` - The list of hostnames the IIIF server should respond to, with the canonical name listed first
- `allow_from_referers` - A regular expression to match against the Referer header for pass-through authorization
- `api_token_secret` - The secret used to encrypt/decrypt JavaScript Web Tokens
- `certificate_domain` - The domain name linked to the SSL certificate to be used
- `dc_api_endpoint` - The public endpoint for DC API

## Outputs

- `endpoint` - The base URL of the IIIF service

## Remote State

### Direct Access

```
data "terraform_remote_state" "iiif" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/iiif.tfstate"
  }
}
```

Outputs are available on `data.remote_state.iiif.outputs.*`

### Module Access

```
module "iiif" {
  source = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "iiif"
}
```

Outputs are available on `module.iiif.outputs.*`

## Upgrading the IIIF Server

This manifest deploys an [AWS Serverless Application Repository](https://aws.amazon.com/serverless/serverlessrepo/) application published and maintained by the Samvera Community [serverless-iiif](https://github.com/samvera-labs/serverless-iiif) project.

In one _very rare_ circumstance (if the upstream template adds a new parameter _and_ you want to apply a change that uses that parameter), you may need to upgrade the application manually before you can apply a terraform change.

1. Retrieve the parameters used to create the stack:

   ```
   $ stack_name=$(terraform output -json | jq -r '.stack_name.value')
   $ params=$(aws cloudformation describe-stacks --stack-name serverlessrepo-$stack_name | \
     jq -cr '[.Stacks[0].Parameters[] | { Name: .ParameterKey, Value: .ParameterValue}]')
   ```

2. Create a CloudFormation changeset to upgrade the stack in place:

   ```
   $ changeset_id=$(aws serverlessrepo create-cloud-formation-change-set \
     --application-id arn:aws:serverlessrepo:us-east-1:625046682746:applications/serverless-iiif \
     --stack-name $stack_name \
     --capabilities CAPABILITY_IAM CAPABILITY_RESOURCE_POLICY \
     --parameter-overrides "$params" | jq -r '.ChangeSetId')
   ```

3. Apply the changeset:

   ```
   $ aws cloudformation execute-change-set --change-set-name $changeset_id
   ```

The upgrade may take several minutes to complete. You can monitor the progress in the [Lambda Application Console](https://console.aws.amazon.com/lambda/home#/applications)
