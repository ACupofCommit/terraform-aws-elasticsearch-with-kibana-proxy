// https://dev.to/suparnatural/aws-elasticsearch-with-serverless-lambda-2m9b

import { APIGatewayProxyHandler } from 'aws-lambda'
import { Client } from '@elastic/elasticsearch'
import AWS from 'aws-sdk'
// @ts-expect-error
import createAwsElasticsearchConnector from 'aws-elasticsearch-connector'

const awsConfig = new AWS.Config({})
const ES_HOST = process.env.ES_HOST
console.log(ES_HOST)

export const index: APIGatewayProxyHandler = async (event) => {
  const client = new Client({
    ...createAwsElasticsearchConnector(awsConfig),
    node: `https://${ES_HOST}`,
  })

  const res = await client.indices.get({
    index: 'kibana_sample_data_logs',
  })
  console.log('res.statusCode: ' + res.statusCode)
  console.log('res.body: ')
  console.log(JSON.stringify(res.body,null,2))

  return {
    body: "hello",
    statusCode: 200,
  }
}
