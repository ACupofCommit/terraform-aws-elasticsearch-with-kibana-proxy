# terraform-aws-elasticsearch

## Update ecs task definition

1. Modify tf code
2. Taint terraform task definition state.

```
$ terraform taint module.module-name.aws_ecs_task_definition.main
$ terraform taint module.module-name.aws_ecs_service.main
```

## Nginx proxy local test

```
$ ENCODED_CONFIG=$(cat assets/default.template | base64)
$ docker run --rm \
    -eKIBANA_HOST=KIBANA_HOST \
    -eES_HOST=es-host.test.com \
    -eCOGNITO_HOST=cognito-host.test.com \
    -eCOGNITO_CLIENT_ID=COGNITO_CLIENT_ID \
    -eAWS_REGION=AWS_REGION \
    -eUSER_POOL_DOMAIN=USER_POOL_DOMAIN \
    -p8080:80 \
    nginx:1.19.9-alpine \
    /bin/sh -c "echo $ENCODED_CONFIG | base64 -d > /tmp/default.template && envsubst < /tmp/default.template > /etc/nginx/conf.d/default.conf && cat /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.14.0 |
| aws | ~> 3.0 |
| random | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 3.0 |
| random | ~> 3.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| associate\_alb | n/a | `bool` | `true` | no |
| associate\_nlb | n/a | `bool` | `false` | no |
| create\_kibana\_proxy | n/a | `bool` | `false` | no |
| es\_node\_number | Use it when you want to create es with nodes smaller than the number of private\_subnets provided. It only makes sense when using vpc. | `number` | `null` | no |
| kibana\_proxy\_host | Domain for kibana access | `string` | `""` | no |
| name\_prefix | n/a | `string` | `"terraform-es"` | no |
| name\_suffix | n/a | `string` | n/a | yes |
| private\_subnets | n/a | `list(string)` | `[]` | no |
| private\_subnets\_cidr\_blocks | n/a | `list(string)` | `[]` | no |
| public\_subnets | n/a | `list(string)` | `[]` | no |
| public\_subnets\_cidr\_blocks | n/a | `list(string)` | `[]` | no |
| route53\_zone\_id | Route53 zone id for kibana\_proxy\_host | `string` | `""` | no |
| service\_ingress\_cidr\_rules | n/a | `list(string)` | <pre>[<br>  "0.0.0.0/0"<br>]</pre> | no |
| tags | n/a | `map(string)` | `{}` | no |
| vpc\_cidr | n/a | `string` | `""` | no |
| vpc\_id | n/a | `string` | `""` | no |

## Outputs

No output.

