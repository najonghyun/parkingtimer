/**
 * Play 스토어 등록에 필수인 개인정보처리방침 공개 페이지.
 *
 * 알림 발송용 워커에 정적 페이지를 얹은 건 실용적인 선택이다 — 이미 배포돼
 * 있고 공개 URL이 있는 유일한 호스팅이라, 방침 하나 때문에 새 계정이나
 * 서비스를 늘리지 않으려고 여기에 붙였다.
 *
 * 원문(수정은 여기와 함께): `store/privacy-policy.md`
 */

const LAST_UPDATED = '2026년 8월 4일';

export const PRIVACY_POLICY_HTML = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>차빼요 개인정보처리방침</title>
<style>
  :root { color-scheme: light dark; }
  body {
    margin: 0 auto; padding: 32px 20px 80px; max-width: 720px;
    font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo",
      "Malgun Gothic", system-ui, sans-serif;
    line-height: 1.75; color: #1b1e24; background: #ffffff;
    word-break: keep-all; overflow-wrap: break-word;
  }
  @media (prefers-color-scheme: dark) {
    body { color: #f2f0eb; background: #1b1e24; }
    td, th { border-color: #333844 !important; }
    th { background: #262a33 !important; }
    a { color: #7fd1a8; }
  }
  h1 { font-size: 1.7rem; margin: 0 0 4px; letter-spacing: -0.5px; }
  h2 { font-size: 1.15rem; margin: 40px 0 10px; letter-spacing: -0.3px; }
  .updated { color: #8b93a1; font-size: 0.9rem; margin: 0 0 28px; }
  .tablewrap { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 0.94rem; }
  th, td { border: 1px solid #dcdfe5; padding: 9px 12px; text-align: left; }
  th { background: #f4f5f7; font-weight: 600; }
  strong { font-weight: 700; }
  a { color: #2f7d55; }
  footer { margin-top: 48px; color: #8b93a1; font-size: 0.9rem; }
</style>
</head>
<body>
<h1>차빼요 개인정보처리방침</h1>
<p class="updated">최종 수정일: ${LAST_UPDATED}</p>

<p>'차빼요'(이하 "앱")는 이용자의 개인정보를 소중히 여기며, 앱을 제공하는 데
반드시 필요한 최소한의 정보만 처리합니다. 본 방침은 앱이 어떤 정보를 수집하고
어떻게 이용하는지 설명합니다.</p>

<h2>1. 수집하는 정보</h2>
<p>앱은 <strong>이름, 이메일, 전화번호, 주소, 위치정보 등 개인을 식별할 수 있는
정보를 일절 수집하지 않습니다.</strong> 별도의 회원가입이나 로그인 절차도 없습니다.</p>
<p>알림 기능을 제공하기 위해 다음 정보가 처리됩니다.</p>
<div class="tablewrap">
<table>
  <tr><th>항목</th><th>내용</th><th>목적</th></tr>
  <tr><td>익명 식별자</td><td>Firebase 익명 인증이 자동 생성하는 임의의 ID</td><td>알림을 보낼 기기를 구분</td></tr>
  <tr><td>기기 알림 토큰</td><td>Firebase Cloud Messaging(FCM)이 발급하는 푸시 토큰</td><td>해당 기기로 알림 전송</td></tr>
  <tr><td>예약된 알림 정보</td><td>알림이 울릴 시각과 표시할 문구</td><td>예약 시각에 알림 발송</td></tr>
</table>
</div>
<p>익명 식별자는 이용자 개인과 연결되지 않으며, 앱을 삭제하고 다시 설치하면
새로운 값이 생성되어 이전 데이터와 연결되지 않습니다.</p>

<h2>2. 기기에만 저장되는 정보</h2>
<p>주차 시각 기록, 주차 횟수, 선택한 주차 제한 시간, 알림 설정은
<strong>이용자의 기기 내부에만 저장</strong>되며 외부로 전송되지 않습니다.
앱을 삭제하면 함께 삭제됩니다.</p>

<h2>3. 정보의 이용 목적</h2>
<p>수집된 정보는 <strong>주차 시간 알림을 정해진 시각에 전송하는 목적으로만</strong>
사용됩니다. 광고, 마케팅, 이용자 분석, 프로파일링 목적으로 이용하지 않습니다.</p>

<h2>4. 제3자 제공 및 처리 위탁</h2>
<p>앱은 이용자의 정보를 제3자에게 판매하거나 제공하지 않습니다. 다만 알림 전송을
위해 다음 서비스를 이용하며, 각 서비스는 해당 목적 범위에서만 정보를 처리합니다.</p>
<ul>
  <li><strong>Google Firebase</strong> (익명 인증, Cloud Firestore, Cloud Messaging)
      — 제공자: Google LLC ·
      <a href="https://firebase.google.com/support/privacy">개인정보처리방침</a></li>
  <li><strong>Cloudflare Workers</strong> — 예약된 알림을 정해진 시각에 발송하는 서버
      — 제공자: Cloudflare, Inc. ·
      <a href="https://www.cloudflare.com/privacypolicy/">개인정보처리방침</a></li>
</ul>

<h2>5. 보유 및 파기</h2>
<p>예약된 알림 정보는 발송 여부와 관계없이 <strong>생성된 날의 자정(한국 시간)이
지나면 자동으로 삭제</strong>됩니다. 앱을 삭제하면 기기에 저장된 모든 기록이 함께
삭제되며, 이후 서버에 남아 있던 알림 정보도 위 주기에 따라 자동 삭제됩니다.</p>

<h2>6. 이용자의 권리</h2>
<p>앱을 삭제하는 것만으로 기기에 저장된 모든 정보를 즉시 삭제할 수 있습니다.
알림 수신은 앱 내 알림 토글 또는 기기의 알림 설정에서 언제든지 끌 수 있습니다.
서버에 저장된 정보의 삭제를 원하시면 아래 연락처로 요청해 주세요.</p>

<h2>7. 아동의 개인정보</h2>
<p>앱은 만 14세 미만 아동을 대상으로 하지 않으며, 아동의 개인정보를 의도적으로
수집하지 않습니다.</p>

<h2>8. 방침의 변경</h2>
<p>본 방침이 변경되는 경우 본 문서의 최종 수정일을 갱신하여 공지합니다.</p>

<h2>9. 문의처</h2>
<p>개인정보 관련 문의: <a href="mailto:i0364842@gmail.com">i0364842@gmail.com</a></p>

<footer>차빼요 (Chabbaeyo)</footer>
</body>
</html>`;
