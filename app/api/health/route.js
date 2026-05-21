export async function GET() {
  return Response.json(
  { status: "failed", message: "Server is not healthy", uptime: process.uptime(),
    hostname: process.env.HOSTNAME || "unknown"
  }, { status: 500 });
}