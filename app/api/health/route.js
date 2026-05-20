export async function GET() {
  return Response.json(
  { status: "ok",
    hostname: process.env.HOSTNAME || "unknown"
  }, { status: 200 });
}