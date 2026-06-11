// frontend/src/app/api/check-connection/route.ts
import { NextResponse } from 'next/server';


// FIX: Forces Next.js to skip build-time static generation for this route
export const dynamic = 'force-dynamic';

export async function GET() {
  // Use the local docker network alias or the public ALB path to reach NestJS
  // We use localhost:3001/api/health here because both live on the same host EC2
  const BACKEND_URL = process.env.INTERNAL_BACKEND_URL || 'http://localhost:3001/api/health';

  try {
    const startTime = Date.now();

    // FIX: Using a traditional controller setup to avoid triggering modern TypeScript checks
    const controller = new AbortController();
    const id = setTimeout(() => controller.abort(), 5000);

    // Added a short timeout configuration to prevent hanging builds if fallback triggers
    const response = await fetch(BACKEND_URL, { 
      cache: 'no-store',
      signal: controller.signal 
    });

    clearTimeout(id); // Clear timeout on success
    
    const backendData = await response.json();
    const duration = Date.now() - startTime;

    return NextResponse.json({
      status: 'success',
      frontend: {
        status: 'healthy',
        message: 'Next.js frontend is running perfectly'
      },
      backend: {
        status: response.ok ? 'connected' : 'disconnected',
        httpCode: response.status,
        responseTimeMs: duration,
        payload: backendData
      }
    });
  } catch (error: any) {
    return NextResponse.json({
      status: 'failed',
      frontend: { status: 'healthy' },
      backend: { 
        status: 'unreachable', 
        error: error.message || 'Could not reach NestJS backend container' 
      }
    }, { status: 502 });
  }
}
