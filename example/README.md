# example

## terraform apply

```
$ terraform init
$ terraform apply -target module.vpc
$ terraform apply
```

> In order to calculate the count value, `module.vpc` must be deployed first.

## Deploy example lambda function
This is an example of a lambda function that accesses elasticsearch
and sends a log or executes a query.

Refer to outputs of terraform apply, set environments like belows:
```
export LAMBDA_EXECUTION_ROLE_ARN=arn:aws:iam::530000000092:role/ewkp-example-lambda-excution-role
export ES_HOST=vpc-ewkp-example-acd3-jovvoucu376smmizrn4c4g6lbe.ap-northeast-1.es.amazonaws.com
export ES_NAME=ewkp-example-acd3
export SECURITY_GROUP_ID=sg-0a94fc7a7329ff7c5
export PRIVATE_SUBNET_ID1=subnet-0f3e7bdcd50bf0302
export PRIVATE_SUBNET_ID2=subnet-03efba21bd494c9d5
```

Then you can deploy lambda function using
[serverless framework](https://www.serverless.com/framework/docs/) .
```
$ yarn
$ yarn deploy
```

## Show logs
You can check the logs of the lambda function using
[AWS SAM cli](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html).

```
$ sam logs -t -n ewkp-example-test-main
```
