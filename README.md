# agrikarta-API

Backend starter structure for AGRI-KARTA Mid-Mile logistics orchestration.

## Structure

- `/supabase/functions/payment-callback` - TypeScript edge function for payment callback orchestration.
- `/supabase/migrations` - PostgreSQL DDL migrations including enums, tables, spatial logic, triggers, and pg_cron setup.

## Notes

- Set `PAYMENT_CALLBACK_SECRET` in Supabase Edge Function secrets; webhook signatures are validated through `x-payment-signature` (HMAC-SHA256).
- `factory_center` stores the central factory coordinate used by zone auto-calculation.
- `zona_sla` stores per-zone delivery SLA (hours) used to auto-populate `tenggat_waktu_kirim`.
