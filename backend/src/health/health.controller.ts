import { Controller, Get } from '@nestjs/common';
import {
  HealthCheck,
  HealthCheckService,
  HttpHealthIndicator,
} from '@nestjs/terminus';

@Controller('api/health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private http: HttpHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  async check() {
    // Do NOT add :3000 or :3001 here. Let the ALB handle it via port 80.
    const frontendUrl = process.env.FRONTEND_URL || 'http://test-lb-for-ec2-demo-1863212643.ap-south-1.elb.amazonaws.com';

    try {
      return await this.health.check([
        // This pings the main frontend homepage via the ALB over standard port 80
        () => this.http.pingCheck('frontend-app', `${frontendUrl}`),
      ]);
    } catch (error) {
      // FALLBACK: If Next.js isn't up yet during boot, return a temporary safe status 
      // so Docker doesn't kill the NestJS container prematurely..
      return {
        status: 'error',
        message: 'Frontend application endpoint unreachable during bootup sequence',
        details: { status: 'booting' }
      };
    }
  }
}