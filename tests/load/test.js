import http from 'k6/http';
import { sleep } from 'k6';
import { Counter } from 'k6/metrics';

export const requests = new Counter('http_reqs');

export const options = {
    stages: [
        { target: 1000, duration: '1m' },  // ramp up to 1000 VUs over 1 minute
        { target: 1000, duration: '5m' },  // sustain 1000 VUs for 5 minutes
        { target: 0, duration: '30s' },    // ramp down to 0 VUs
    ],
    thresholds: {
        // Acceptable failure rate, e.g. less than 1% errors
        'http_req_failed': ['rate<0.01'],
        // 95% of requests must finish below 1 second
        'http_req_duration': ['p(95)<1000'],
    },
};

export default function () {
    const res = http.get('http://localhost:8081/');
    requests.add(1);

    // Reduce sleep to increase request rate per VU (or remove it)
    sleep(0.1); 
}
