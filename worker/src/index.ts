/**
 * Runs every minute (see wrangler.toml [triggers]). Finds every scheduled
 * parking alert whose fire time has passed, sends it via FCM, and marks it
 * sent — so Android delivery survives OEM background-restriction lists that
 * would otherwise silently kill a local AlarmManager alarm.
 *
 * No `firebase-admin` here: Workers' V8 isolate can't run the Node-only
 * Admin SDK, so this hand-rolls a Google OAuth2 service-account token
 * (RS256 JWT via Web Crypto) and talks to Firestore + FCM over their plain
 * REST APIs instead.
 */

import { PRIVACY_POLICY_HTML } from './privacy';

export interface Env {
  /** Full contents of the downloaded GCP service account JSON key file. */
  GCP_SERVICE_ACCOUNT_JSON: string;
  FIREBASE_PROJECT_ID: string;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

interface DueAlert {
  /** Full Firestore resource name, e.g. `projects/x/databases/(default)/documents/users/UID/scheduledAlerts/ID`. */
  name: string;
  title: string;
  body: string;
  kind: string;
  channelId: string;
  /** `#rrggbb` icon tint, computed app-side from the app palette. */
  color: string;
  fcmToken: string;
}

const OAUTH_SCOPES = [
  'https://www.googleapis.com/auth/datastore',
  'https://www.googleapis.com/auth/firebase.messaging',
];

export default {
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(runOnce(env));
  },

  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Play 스토어 등록에 필요한 공개 개인정보처리방침 URL.
    if (url.pathname === '/privacy') {
      return new Response(PRIVACY_POLICY_HTML, {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'public, max-age=3600',
        },
      });
    }

    // Lets `wrangler dev --test-scheduled` (or a manual curl) trigger a run
    // without waiting for the real cron tick.
    if (url.pathname === '/__run') {
      const sent = await runOnce(env);
      return Response.json({ sent });
    }
    return new Response('parking-timer-worker: /privacy, /__run', { status: 200 });
  },
};

async function runOnce(env: Env): Promise<number> {
  const serviceAccount: ServiceAccount = JSON.parse(env.GCP_SERVICE_ACCOUNT_JSON);
  const projectId = env.FIREBASE_PROJECT_ID || serviceAccount.project_id;

  const accessToken = await getAccessToken(serviceAccount, OAUTH_SCOPES);
  const dueAlerts = await queryDueAlerts(projectId, accessToken);

  for (const alert of dueAlerts) {
    try {
      await sendPush(projectId, accessToken, alert);
    } catch (e) {
      console.error(`FCM send failed for ${alert.name}:`, e);
    }
    try {
      // Mark sent regardless of send outcome — a stale/invalid token would
      // otherwise fail forever and spam retries every minute.
      await markSent(alert.name, accessToken);
    } catch (e) {
      console.error(`Failed to mark ${alert.name} as sent:`, e);
    }
  }

  try {
    await deleteExpiredAlerts(projectId, accessToken);
  } catch (e) {
    console.error('만료 문서 정리 실패:', e);
  }

  return dueAlerts.length;
}

/**
 * Deletes any alert doc past its `expireAt` (set by the app to the next
 * midnight KST after creation — no Firestore-native TTL policy since that
 * requires GCP billing enabled, which this project intentionally avoids).
 */
async function deleteExpiredAlerts(projectId: string, accessToken: string): Promise<void> {
  const nowIso = new Date().toISOString();
  const requestBody = {
    structuredQuery: {
      from: [{ collectionId: 'scheduledAlerts', allDescendants: true }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'expireAt' },
          op: 'LESS_THAN_OR_EQUAL',
          value: { timestampValue: nowIso },
        },
      },
      limit: 200,
    },
  };

  const resp = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    },
  );
  if (!resp.ok) {
    throw new Error(`만료 문서 조회 실패: ${resp.status} ${await resp.text()}`);
  }

  const rows = (await resp.json()) as Array<{ document?: { name: string } }>;
  for (const row of rows) {
    const name = row.document?.name;
    if (!name) continue;
    const delResp = await fetch(`https://firestore.googleapis.com/v1/${name}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!delResp.ok) {
      console.error(`만료 문서 삭제 실패 (${name}): ${delResp.status} ${await delResp.text()}`);
    }
  }
}

async function queryDueAlerts(
  projectId: string,
  accessToken: string,
): Promise<DueAlert[]> {
  const nowIso = new Date().toISOString();
  const requestBody = {
    structuredQuery: {
      from: [{ collectionId: 'scheduledAlerts', allDescendants: true }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            {
              fieldFilter: {
                field: { fieldPath: 'sent' },
                op: 'EQUAL',
                value: { booleanValue: false },
              },
            },
            {
              fieldFilter: {
                field: { fieldPath: 'fireAt' },
                op: 'LESS_THAN_OR_EQUAL',
                value: { timestampValue: nowIso },
              },
            },
          ],
        },
      },
      limit: 200,
    },
  };

  const resp = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    },
  );
  if (!resp.ok) {
    throw new Error(`Firestore query failed: ${resp.status} ${await resp.text()}`);
  }

  const rows = (await resp.json()) as Array<{
    document?: { name: string; fields?: Record<string, any> };
  }>;

  const alerts: DueAlert[] = [];
  for (const row of rows) {
    const doc = row.document;
    if (!doc) continue; // heartbeat rows with no document
    const f = doc.fields ?? {};
    alerts.push({
      name: doc.name,
      title: f.title?.stringValue ?? '',
      body: f.body?.stringValue ?? '',
      kind: f.kind?.stringValue ?? '',
      channelId: f.channelId?.stringValue ?? '',
      color: f.color?.stringValue ?? '',
      fcmToken: f.fcmToken?.stringValue ?? '',
    });
  }
  return alerts;
}

async function sendPush(
  projectId: string,
  accessToken: string,
  alert: DueAlert,
): Promise<void> {
  if (!alert.fcmToken) throw new Error('알림 문서에 fcmToken이 없습니다');

  const message = {
    message: {
      token: alert.fcmToken,
      // "notification" payload → Play Services renders it directly even if
      // the app process is dead or OEM-restricted.
      notification: { title: alert.title, body: alert.body },
      // "data" payload → lets the app redraw it itself via the same local
      // channel when it's already in the foreground.
      data: {
        kind: alert.kind,
        title: alert.title,
        body: alert.body,
      },
      android: {
        // FCM v1's AndroidConfig.priority enum is uppercase ("HIGH"/"NORMAL").
        priority: 'HIGH',
        notification: {
          // References a channel the app pre-registered on launch, so
          // vibration pattern / sound-on-off are whatever that channel
          // was configured with. NOTE: the FCM v1 REST API's JSON body
          // uses camelCase (protobuf JSON mapping) — `channel_id` here is
          // silently ignored by the API, which is why sound (and the
          // per-stage vibration pattern) wasn't taking effect.
          channelId: alert.channelId,
          // 매너모드에서는 소리를 낼 수 없어(안드로이드가 알림 채널의
          // USAGE_ALARM 요청을 발송 시점에 무시함) 진동 외의 구분 수단이
          // 시각적인 것뿐이다. 위험은 진한 빨강 + 눌러도 안 사라지는 알림,
          // 경고는 주황 + 누르면 사라짐.
          ...(alert.color ? { color: alert.color } : {}),
          sticky: alert.kind === 'danger',
        },
      },
    },
  };

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    },
  );
  if (!resp.ok) {
    throw new Error(`FCM send failed: ${resp.status} ${await resp.text()}`);
  }
}

async function markSent(documentName: string, accessToken: string): Promise<void> {
  const url = `https://firestore.googleapis.com/v1/${documentName}?updateMask.fieldPaths=sent`;
  const resp = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields: { sent: { booleanValue: true } } }),
  });
  if (!resp.ok) {
    throw new Error(`Firestore update failed: ${resp.status} ${await resp.text()}`);
  }
}

// ---- Google service-account OAuth2 (RS256 JWT bearer flow) ----------------
// Hand-rolled because `google-auth-library`/`firebase-admin` need Node APIs
// that don't exist in the Workers runtime; Web Crypto covers RS256 signing.

async function getAccessToken(
  serviceAccount: ServiceAccount,
  scopes: string[],
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: scopes.join(' '),
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const unsigned = `${base64urlEncodeJson(header)}.${base64urlEncodeJson(claimSet)}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64urlEncodeBuffer(signature)}`;

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!resp.ok) {
    throw new Error(`구글 OAuth2 토큰 교환 실패: ${resp.status} ${await resp.text()}`);
  }
  const json = (await resp.json()) as { access_token: string };
  return json.access_token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64urlEncodeJson(value: unknown): string {
  return base64urlEncodeBuffer(new TextEncoder().encode(JSON.stringify(value)).buffer);
}

function base64urlEncodeBuffer(buf: ArrayBufferLike): string {
  const bytes = new Uint8Array(buf);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
