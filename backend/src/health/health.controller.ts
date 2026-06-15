import { Controller, Get, Logger } from '@nestjs/common';
import {
  HealthCheck,
  HealthCheckService,
  HttpHealthIndicator,
} from '@nestjs/terminus';

@Controller('api/health')
export class HealthController {
  private readonly logger = new Logger(HealthController.name);

  constructor(
    private health: HealthCheckService,
    private http: HttpHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  async check() {
    const frontendUrl = process.env.FRONTEND_URL || 'http://test-lb-for-ec2-demo-1863212643.ap-south-1.elb.amazonaws.com';
    try {
      const result = await this.health.check([
        () => this.http.pingCheck('frontend-app', `${frontendUrl}`),
      ]);
      this.logger.log('Health check passed');
      return result;
    } catch (error) {
      this.logger.warn('Frontend unreachable during health check');
      return {
        status: 'error',
        message: 'Frontend application endpoint unreachable during bootup sequence',
        details: { status: 'booting' }
      };
    }
  }
}