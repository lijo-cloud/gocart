import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';

// Optional: Enable internal OTel debugging logs if troubleshooting is needed
diag.setLogger(diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.INFO));

// The default OTLP endpoint points locally because Alloy will act as the local proxy agent
const oltpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4317';

const traceExporter = new OTLPTraceExporter({
  url: oltpEndpoint,
});

export const otelSDK = new NodeSDK({
  serviceName: 'gocart-backend-api',
  traceExporter: traceExporter,
  instrumentations: [
    getNodeAutoInstrumentations({
      // Protects database connection security string lookups
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

// Gracefully handle shutdown signals
process.on('SIGTERM', () => {
  otelSDK.shutdown()
    .then(() => console.log('SDK shut down successfully'))
    .catch((err) => console.log('Error shutting down SDK', err))
    .finally(() => process.exit(0));
});
