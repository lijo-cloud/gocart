export async function GET() {
  return Response.json(
  { status: "failed",
    hostname: process.env.HOSTNAME || "unknown"
  }, { status: 500 });
}