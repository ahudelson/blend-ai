import React from 'react';
import ReactDOM from 'react-dom';
import './index.css';
import App from './App';
import { Amplify } from '@aws-amplify/core';
import { BrowserRouter } from 'react-router-dom';

Amplify.configure({
  Auth: {
    region: 'us-east-1',
    userPoolId: '<user_pool_id>',  // From tofu output
    userPoolWebClientId: 'user_pool_client',  // From tofu output
    mandatorySignIn: true,
    oauth: {
      domain: '<user_pool_domain>',  // From tofu output
      scope: ['email', 'openid', 'profile'],
      // Update <BASE_URL> with your unique domain name
      redirectSignIn: '<BASE_URL>/callback',
      // Update <BASE_URL> with your unique domain name
      redirectSignOut: '<BASE_URL>/logout',
      responseType: 'code'
    }
  }
});

ReactDOM.render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>,
  document.getElementById('root')
);