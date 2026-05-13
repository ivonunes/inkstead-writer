import { Readable } from "node:stream";
import { handleWriterLocalApi } from "../../src/core/writer/local-api.js";

type LocalApiConfig = Parameters<typeof handleWriterLocalApi>[3];

export async function localApi(method: string, url: string, body: unknown, root: string, config: LocalApiConfig): Promise<{ status: number; body: unknown }> {
  const request = Readable.from(body === undefined ? [] : [JSON.stringify(body)]) as unknown as Parameters<typeof handleWriterLocalApi>[0];
  request.method = method;
  request.url = url;
  let status = 0;
  let responseBody = "";
  const response = {
    writeHead(nextStatus: number) {
      status = nextStatus;
    },
    end(chunk: string) {
      responseBody = chunk;
    }
  } as unknown as Parameters<typeof handleWriterLocalApi>[1];
  await handleWriterLocalApi(request, response, root, config);
  return { status, body: JSON.parse(responseBody) };
}
