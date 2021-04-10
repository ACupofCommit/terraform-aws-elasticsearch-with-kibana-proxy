# terraform-aws-elasticsearch-with-kibana-proxy
This module is the Terraform code to provide the AWS **Elasticsearch Service**
inside AWS VPC and ECS Fargate Nginx proxy server
so that you can access kibana from outside.

## Test nginx proxy in local

```
$ ENCODED_CONFIG=$(cat assets/default.template | base64)
$ docker run --rm \
    -eKIBANA_HOST=KIBANA_HOST \
    -eES_HOST=es-host.test.com \
    -p8080:80 \
    nginx:1.19.9-alpine \
    /bin/sh -c "echo $ENCODED_CONFIG | base64 -d > /tmp/default.template && envsubst < /tmp/default.template > /etc/nginx/conf.d/default.conf && cat /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
```

## Update ecs task definition

1. Modify `.tf` or `default.template` file.
2. Taint terraform task definition state then apply it. Example:

```
$ terraform taint module.module-name.aws_ecs_task_definition.main
$ terraform apply
```

3. Go AWS ECS Console, select cluster - Service - `Update`
   then select the latest task definition

## Default master user password
The default master user's name is `admin` and password is `Change-me!-123`.
When you first access Kibana, please change your password
from the profile icon `Reset password` menu in the upper right corner.

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
| es\_ebs\_volume\_size | n/a | `number` | `10` | no |
| es\_instance\_type | n/a | `string` | `"t3.medium.elasticsearch"` | no |
| es\_master\_user\_arn | n/a | `string` | `null` | no |
| es\_master\_user\_password | n/a | `string` | `"Change-me!-123"` | no |
| es\_node\_number | Use it when you want to create es with nodes smaller than the number of private\_subnets provided. It only makes sense when using vpc. | `number` | `null` | no |
| kibana\_custom\_domain | Domain for kibana access | `string` | n/a | yes |
| name\_prefix | For most of resource names | `string` | `"terraform-es"` | no |
| name\_suffix | If omitted, random string is used. | `string` | n/a | yes |
| private\_subnets | n/a | `list(string)` | `[]` | no |
| private\_subnets\_cidr\_blocks | n/a | `list(string)` | `[]` | no |
| public\_subnets | n/a | `list(string)` | `[]` | no |
| public\_subnets\_cidr\_blocks | n/a | `list(string)` | `[]` | no |
| route53\_zone\_id | Route53 zone id for kibana\_proxy\_host | `string` | n/a | yes |
| service\_ingress\_cidr\_rules | n/a | `list(string)` | <pre>[<br>  "0.0.0.0/0"<br>]</pre> | no |
| tags | n/a | `map(string)` | `{}` | no |
| vpc\_id | n/a | `string` | `"If you provide vpc_id, elasticsearch will be deployed in that vpc. Or it is distributed outside the vpc."` | no |

## Outputs

| Name | Description |
|------|-------------|
| output | Resource information for accessing elasticsearch |
