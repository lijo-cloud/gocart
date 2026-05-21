export async function GET() {
  return Response.json(
  { status: "ok", message: "Server is healthy", uptime: process.uptime(),
    hostname: process.env.HOSTNAME || "unknown"
  }, { status: 200 });
}