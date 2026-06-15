import { Module } from '@nestjs/common';
import { LoggerModule } from 'nestjs-pino';
import { trace, context } from '@opentelemetry/api';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { HealthModule } from './health/health.module';

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL || 'info',
        formatters: {
          log(object) {
            // Inject traceId and spanId from active OpenTelemetry span
            const span = trace.getActiveSpan();
            if (span) {
              const ctx = span.spanContext();
              return {
                ...object,
                traceId: ctx.traceId,
                spanId: ctx.spanId,
              };
            }
            return object;
          },
        },
        transport: process.env.NODE_ENV !== 'production'
          ? { target: 'pino-pretty' }
          : undefined,
      },
    }),
    HealthModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}