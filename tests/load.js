import http from 'k6/http';
import { check, sleep } from 'k6';

const target = __ENV.TARGET_URL || 'http://127.0.0.1:8081/';
const vus = Number(__ENV.VUS || 10);
const duration = __ENV.DURATION || '60s';

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  vus,
  duration,
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<2000']
  }
};

export default function () {
  const response = http.get(target, {
    headers: { 'Connection': 'keep-alive' },
    tags: { target }
  });
  check(response, {
    'status 200': (r) => r.status === 200,
    'body esperado': (r) => r.body.includes('status')
  });
  sleep(0.1);
}
