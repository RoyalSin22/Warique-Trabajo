// backend/src/config/env.validation.ts
// Fail fast at startup if required configuration is missing or insecure.
export function validateEnv(config: Record<string, unknown>): Record<string, unknown> {
  for (const key of ['DATABASE_URL', 'JWT_SECRET']) {
    if (!config[key]) {
      throw new Error(`Missing environment variable: ${key}`);
    }
  }

  const jwtSecret = String(config.JWT_SECRET);
  if (jwtSecret.length < 32 || jwtSecret.startsWith('CHANGE_ME')) {
    throw new Error('JWT_SECRET must be a random value of at least 32 characters');
  }

  const expiresIn = Number(config.JWT_EXPIRES_IN_SECONDS ?? 43200);
  if (!Number.isInteger(expiresIn) || expiresIn <= 0) {
    throw new Error('JWT_EXPIRES_IN_SECONDS must be a positive integer');
  }

  const utcOffset = Number(config.BUSINESS_UTC_OFFSET_MINUTES ?? -300);
  if (!Number.isInteger(utcOffset) || utcOffset < -720 || utcOffset > 840) {
    throw new Error('BUSINESS_UTC_OFFSET_MINUTES must be an integer between -720 and 840');
  }

  const port = Number(config.PORT ?? 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535');
  }

  return config;
}
