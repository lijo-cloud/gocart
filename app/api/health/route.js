export async function GET() {
  return Response.json(
  { status: "ok", message: "Server is healthy", uptime: process.uptime(),
    hostname: process.env.HOSTNAME || "unknown"
  }, { status: 200 });
}


// Add this handler to test your POST requests
export async function POST(request) {
  try {
    // This forces Node.js to read the incoming body stream from 'hey'
    const body = await request.text(); 
    
    return Response.json(
      { 
        status: "success", 
        message: "POST request processed", 
        receivedBytes: body.length,
        hostname: process.env.HOSTNAME || "unknown"
      }, 
      { status: 200 }
    );
  } catch (error) {
    return Response.json(
      { status: "error", message: "Failed to parse body" }, 
      { status: 400 }
    );
  }
}