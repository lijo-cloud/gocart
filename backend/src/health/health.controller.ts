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
  check() {
    return this.health.check([
      // This forces NestJS to ping the frontend's database-testing route over the internal network
      () => this.http.pingCheck('frontend-database', 'http://app-web-1:3000/api/db-test'),
    ]);
  }
}