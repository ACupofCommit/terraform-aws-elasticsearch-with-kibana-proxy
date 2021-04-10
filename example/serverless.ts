import type { AWS } from '@serverless/typescript'
import packageJson from './package.json'

const {AWS_DEFAULT_REGION} = process.env
const {SECURITY_GROUP_ID='', PRIVATE_SUBNET_ID1='', PRIVATE_SUBNET_ID2='', ES_NAME, LAMBDA_EXECUTION_ROLE_ARN} = process.env
const {ES_HOST, ES_MASTER_USERNAME, ES_MASTER_PASSWORD} = process.env

const logEnv = (name: string) => console.log(`${name}: ${process.env[name]}`)

if (!AWS_DEFAULT_REGION) throw new Error('AWS_DEFAULT_REGION is required')
if (!ES_HOST) throw new Error('ES_HOST is required')
if (!ES_NAME) throw new Error('ES_NAME is required')
if (!ES_MASTER_USERNAME) throw new Error('ES_MASTER_USERNAME is required')
if (!ES_MASTER_PASSWORD) throw new Error('ES_MASTER_PASSWORD is required')
if (!LAMBDA_EXECUTION_ROLE_ARN) throw new Error('LAMBDA_EXECUTION_ROLE_ARN is required')

if (SECURITY_GROUP_ID && !(PRIVATE_SUBNET_ID1 + PRIVATE_SUBNET_ID2)) {
  throw new Error('SubnetIds and SecurityIds must coexist or be both empty list.')
}
if (!SECURITY_GROUP_ID && (PRIVATE_SUBNET_ID1 + PRIVATE_SUBNET_ID2)) {
  throw new Error('SubnetIds and SecurityIds must coexist or be both empty list.')
}

console.log('REGION: ' + AWS_DEFAULT_REGION)
const serverlessConfiguration: AWS = {
  service: packageJson.name,
  frameworkVersion: '2',
  custom: {
    webpack: {
      packager: 'yarn',
      webpackConfig: './webpack.config.js',
      packagerOptions: {
        noFrozenLockfile: true,
      },
      includeModules: {
        forceExclude: ['aws-sdk'],
      },
    },
    "serverless-offline": {
      lambdaPort: process.env.HTTP_PORT
        ? Number(process.env.HTTP_PORT) + 2
        : 3002,
    },
  },
  // Add the serverless-webpack plugin
  plugins: [
    'serverless-webpack',
    'serverless-offline',
    'serverless-pseudo-parameters',
  ],
  // https://www.serverless.com/framework/docs/deprecations/
  variablesResolutionMode: '20210219',
  provider: {
    name: 'aws',
    stage: 'test',
    // @ts-expect-error
    region: AWS_DEFAULT_REGION,
    lambdaHashingVersion: '20201221',
    runtime: 'nodejs14.x',
    apiGateway: {
      shouldStartNameWithService: true,
      minimumCompressionSize: 1024,
    },
    vpc: {
      securityGroupIds: [SECURITY_GROUP_ID],
      subnetIds: [PRIVATE_SUBNET_ID1, PRIVATE_SUBNET_ID2],
    },
    environment: {
      AWS_NODEJS_CONNECTION_REUSE_ENABLED: '1',
      // https://www.serverless.com/framework/docs/providers/aws/guide/variables#reference-variables-in-javascript-files
    },
    iam: {
      role: LAMBDA_EXECUTION_ROLE_ARN,
    },
  },
  functions: {
    main: {
      handler: 'src/handler.index',
      events: [
        {
          http: { method: 'get', path: '/main' }
        },
      ],
      environment: {
        ES_HOST: ES_HOST,
        ES_MASTER_USERNAME: ES_MASTER_USERNAME,
        ES_MASTER_PASSWORD: ES_MASTER_PASSWORD,
      }
    },
  }
}

module.exports = serverlessConfiguration
