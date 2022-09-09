// This is a loadtest under development
// Test here is spec'd to have 100virtual-users
// Other specs currently similar to smoktest
// But loadtest needs testplan that likely uses auth & data-transfer

import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  stages: [
    { duration: '5m', target: 100 }, // simulate ramp-up of traffic from 1 to 100 users over 5 minutes.
    { duration: '10m', target: 100 }, // stay at 100 users for 10 minutes
    { duration: '5m', target: 0 }, // ramp-down to 0 users fo 5 minutes
  ],
  hosts: {
    'test.ingress-nginx-controller.ga:80': '127.0.0.1:80',
    'test.ingress-nginx-controller.ga:443': '127.0.0.1:443',
  },
  thresholds: {
    http_req_failed: ['rate<0.01'], // http errors should be less than 1%
    http_req_duration: ['p(95)<500'], // 95 percent of response times must be below 500ms
    http_req_duration: ['p(99)<1500'], // 99 percent of response times must be below 1500ms
  },
};

export default function () {
    const BASE_URL = 'https://test.ingress-nginx-controller.ga:443';
    const req1 = {
      method: 'GET',
      url: `${BASE_URL}/ip`,
    };
    const req2 = {
      method: 'GET',
      url: `${BASE_URL}/get`,
    };
    const req3 = {
      params: {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
      },
      method: 'POST',
      url: `${BASE_URL}/post`,
      body: {
        hello: 'world!',
      },
    };
    const res = http.batch([req1, req2, req3]);
    sleep(1);
}
