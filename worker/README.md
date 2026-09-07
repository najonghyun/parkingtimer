# parking-timer-worker

매 1분마다 Firestore에서 발송 시각이 지난(`sent == false && fireAt <= now`) 주차 알림 문서를 찾아 FCM으로 보내고 `sent: true`로 표시하는 Cloudflare Worker입니다. 카드 등록 없이 무료 플랜으로 동작합니다.

## 사전 준비물

- Node.js (이미 설치되어 있음)
- Cloudflare 계정 (무료, 카드 불필요) — https://dash.cloudflare.com/sign-up
- `worker/secrets/parking-worker-key.json` — GCP 서비스 계정 키 (이미 발급됨, `.gitignore`에 등록되어 있어 커밋되지 않음)

## 배포 절차

```bash
cd worker
npm install
npx wrangler login          # 브라우저로 Cloudflare 로그인 (터미널 앱에서 직접 실행)

# 서비스 계정 JSON 파일 전체를 시크릿으로 등록 (한 번만)
npx wrangler secret put GCP_SERVICE_ACCOUNT_JSON < secrets/parking-worker-key.json

npx wrangler deploy
```

`FIREBASE_PROJECT_ID`는 민감 정보가 아니라 `wrangler.toml`의 `[vars]`에 이미 평문으로 들어 있습니다 (`parking-timer-app`).

## 로컬 테스트

```bash
npx wrangler dev
# 다른 터미널에서:
curl http://localhost:8787/__run
```

`/__run`은 실제 cron 틱을 기다리지 않고 즉시 한 번 실행해보는 수동 트리거입니다. 응답으로 이번에 발송한 알림 개수(`sent`)가 나옵니다.

## 배포 후 확인

```bash
npx wrangler tail
```

배포된 Worker의 실시간 로그를 스트리밍합니다. 앱에서 "주차했어요"를 누른 뒤 Firestore 콘솔(`users/{uid}/scheduledAlerts`)에 문서가 쌓이는지, 예정 시각이 지나면 이 로그에 실행 흔적이 뜨고 문서의 `sent`가 `true`로 바뀌는지 확인하세요.

## 만약 실행이 안 뜨거나 지연된다면

- `npx wrangler deployments list` 로 배포가 실제로 반영됐는지 확인
- Cloudflare 대시보드 → Workers & Pages → parking-timer-worker → Triggers 탭에서 Cron Trigger(`* * * * *`)가 활성화되어 있는지 확인
- `npx wrangler tail`로 에러 로그 확인 (권한 부족, 토큰 만료 등은 여기 찍힘)
