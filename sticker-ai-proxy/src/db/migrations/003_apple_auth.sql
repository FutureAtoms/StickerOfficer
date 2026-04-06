-- Migration 003: Apple Sign-In support + unique indexes for social IDs

ALTER TABLE devices ADD COLUMN apple_id TEXT;
ALTER TABLE devices ADD COLUMN apple_email TEXT;
ALTER TABLE devices ADD COLUMN apple_name TEXT;

-- Ensure one-to-one mapping between social accounts and devices
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_google_id ON devices(google_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_apple_id ON devices(apple_id);
