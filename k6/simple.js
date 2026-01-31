import http from 'k6/http';

export const options = {
    vus: 2, 
    duration: '10s'
}

export default () =>{
    const payload = JSON.stringify({
        userid: 57, 
        content: 'Hello, world!'
    });

    // 2. Define params to specify the content type
    const params = {
        headers: {
            'Content-Type': 'application/json',
        },
    };

    http.post('http://172.234.198.14:4000/realtime/post', payload, params);
}