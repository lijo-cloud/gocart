import { Controller, Get, Logger } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

@Controller('api/health')
export class HealthController {
  private readonly logger = new Logger(HealthController.name);

  @Get()
  async check() {
    try {
      await prisma.$queryRaw`SELECT 1`;
      this.logger.log('Health check passed - DB connected');
      return { status: 'ok', db: 'connected' };
    } catch (error) {
      const err = error as Error;
      this.logger.error('DB connection failed', err.message);
      return { status: 'error', db: 'unreachable' };
    }
  }
}