import { S3Client, PutObjectCommand, HeadObjectCommand, DeleteObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { defineSecret } from "firebase-functions/params";

export const r2AccountId = defineSecret("R2_ACCOUNT_ID");
export const r2AccessKeyId = defineSecret("R2_ACCESS_KEY_ID");
export const r2SecretAccessKey = defineSecret("R2_SECRET_ACCESS_KEY");
export const r2Bucket = defineSecret("R2_BUCKET");
export const r2PublicBaseUrl = defineSecret("R2_PUBLIC_BASE_URL");

/** Pass to `secrets:` on any callable/trigger option that touches R2. */
export const R2_SECRETS = [r2AccountId, r2AccessKeyId, r2SecretAccessKey, r2Bucket, r2PublicBaseUrl];

function client(): S3Client {
  return new S3Client({
    region: "auto",
    endpoint: `https://${r2AccountId.value()}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: r2AccessKeyId.value(),
      secretAccessKey: r2SecretAccessKey.value(),
    },
  });
}

export async function presignPutUrl(
  key: string,
  contentType: string,
  expiresInSeconds: number
): Promise<string> {
  const command = new PutObjectCommand({
    Bucket: r2Bucket.value(),
    Key: key,
    ContentType: contentType,
  });
  return getSignedUrl(client(), command, { expiresIn: expiresInSeconds });
}

export async function headObject(key: string): Promise<{ sizeBytes: number } | null> {
  try {
    const result = await client().send(new HeadObjectCommand({ Bucket: r2Bucket.value(), Key: key }));
    return { sizeBytes: result.ContentLength ?? 0 };
  } catch (err) {
    const httpStatus = (err as { $metadata?: { httpStatusCode?: number }; name?: string }).$metadata
      ?.httpStatusCode;
    const name = (err as { name?: string }).name;
    if (name === "NotFound" || name === "NoSuchKey" || httpStatus === 404) {
      return null;
    }
    throw err;
  }
}

export async function deleteObject(key: string): Promise<void> {
  await client().send(new DeleteObjectCommand({ Bucket: r2Bucket.value(), Key: key }));
}

export function publicUrlFor(key: string): string {
  return `${r2PublicBaseUrl.value()}/${key}`;
}
