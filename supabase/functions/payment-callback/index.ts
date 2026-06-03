interface PaymentCallbackPayload {
  payment_id: string;
  order_id: string;
  payment_status: 'paid' | 'failed' | 'pending';
  paid_at?: string;
}

const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
    },
  });

export const paymentCallbackHandler = async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  let payload: PaymentCallbackPayload;
  try {
    payload = (await req.json()) as PaymentCallbackPayload;
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON payload' });
  }

  if (!payload.payment_id || !payload.order_id || !payload.payment_status) {
    return jsonResponse(400, { error: 'Missing required payment callback fields' });
  }

  return jsonResponse(200, {
    success: true,
    message: 'Payment callback accepted for downstream orchestration',
    payment_id: payload.payment_id,
    order_id: payload.order_id,
    payment_status: payload.payment_status,
  });
};

if (typeof Deno !== 'undefined') {
  Deno.serve(paymentCallbackHandler);
}
