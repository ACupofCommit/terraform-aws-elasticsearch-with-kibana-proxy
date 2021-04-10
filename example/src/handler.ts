// https://dev.to/suparnatural/aws-elasticsearch-with-serverless-lambda-2m9b
import { APIGatewayProxyHandler } from 'aws-lambda'
import { Client } from '@elastic/elasticsearch'

const {ES_HOST, ES_MASTER_USERNAME, ES_MASTER_PASSWORD} = process.env

export const index: APIGatewayProxyHandler = async (event) => {
  const client = new Client({
    node: `https://${ES_HOST}`,
    auth: {
      username: ES_MASTER_USERNAME || '',
      password: ES_MASTER_PASSWORD || '',
    }
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
