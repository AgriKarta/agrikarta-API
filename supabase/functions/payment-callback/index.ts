interface PaymentCallbackPayload {
  payment_id: string;
  order_id: string;
  payment_status: 'paid' | 'failed' | 'pending';
  paid_at?: string;
}

const SIGNATURE_HEADER = 'x-payment-signature';

const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
    },
  });

const toHex = (buffer: ArrayBuffer): string =>
  Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');

const timingSafeEqual = (a: string, b: string): boolean => {
  if (a.length !== b.length) {
    return false;
  }

  let mismatch = 0;
  for (let i = 0; i < a.length; i += 1) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }

  return mismatch === 0;
};

const computeHmacSignature = async (payload: string, secret: string): Promise<string> => {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload));
  return toHex(signature);
};

const isValidPaymentCallbackPayload = (value: unknown): value is PaymentCallbackPayload => {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const candidate = value as Record<string, unknown>;
  const allowedStatuses = new Set(['paid', 'failed', 'pending']);

  return (
    typeof candidate.payment_id === 'string' &&
    typeof candidate.order_id === 'string' &&
    typeof candidate.payment_status === 'string' &&
    allowedStatuses.has(candidate.payment_status) &&
    (candidate.paid_at === undefined || typeof candidate.paid_at === 'string')
  );
};

const getPaymentCallbackSecret = (): string | undefined => {
  if (typeof Deno !== 'undefined') {
    return Deno.env.get('PAYMENT_CALLBACK_SECRET');
  }

  if (typeof process !== 'undefined') {
    return process.env.PAYMENT_CALLBACK_SECRET;
  }

  return undefined;
};

export const paymentCallbackHandler = async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  const rawPayload = await req.text();
  const paymentCallbackSecret = getPaymentCallbackSecret();
  if (!paymentCallbackSecret) {
    return jsonResponse(500, { error: 'PAYMENT_CALLBACK_SECRET is not configured' });
  }

  const incomingSignature = req.headers.get(SIGNATURE_HEADER);
  if (!incomingSignature) {
    return jsonResponse(401, { error: 'Missing webhook signature' });
  }

  const expectedSignature = await computeHmacSignature(rawPayload, paymentCallbackSecret);
  if (!timingSafeEqual(incomingSignature, expectedSignature)) {
    return jsonResponse(401, { error: 'Invalid webhook signature' });
  }

  let payload: PaymentCallbackPayload;
  try {
    const parsedPayload: unknown = JSON.parse(rawPayload);
    if (!isValidPaymentCallbackPayload(parsedPayload)) {
      return jsonResponse(400, { error: 'Invalid payment callback schema' });
    }

    payload = parsedPayload;
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON payload' });
  }

  return jsonResponse(200, {
    success: true,
    message: 'Payment callback validated and accepted',
    payment_id: payload.payment_id,
    order_id: payload.order_id,
    payment_status: payload.payment_status,
  });
};

if (typeof Deno !== 'undefined') {
  Deno.serve(paymentCallbackHandler);
}
