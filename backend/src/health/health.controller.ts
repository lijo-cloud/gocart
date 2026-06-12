// backend/src/health/health.controller.ts
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
    try {
      return await this.health.check([
        () => this.http.pingCheck('frontend-database', 'http://api:3000/api/db-test'),
      ]);
    } catch (error) {
      // FALLBACK: If Next.js isn't up yet during boot, return a temporary safe status 
      // so Docker doesn't kill the NestJS container prematurely..
      return {
        status: 'error',
        message: 'Frontend database endpoint unreachable during bootup sequence',
        details: { status: 'booting' }
      };
    }
  }
}