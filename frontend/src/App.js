import React, { useState, useEffect } from 'react';
import { Auth } from '@aws-amplify/auth';  // Auth class for v5
import { Hub } from '@aws-amplify/core';   // Hub from core for v5
import { useHistory } from 'react-router-dom';
import './App.css';

function App() {
  const [prompt, setPrompt] = useState('');
  const [response, setResponse] = useState(null);
  const [user, setUser] = useState(null);
  const history = useHistory();  // Add this

  useEffect(() => {
    Hub.listen('auth', ({ payload: { event, data } }) => {
      if (event === 'signIn') {
        setUser(data);
        history.push('/');  // Redirect to root after sign-in
      }
      if (event === 'signOut') setUser(null);
    });
    checkUser();
  }, [history]);

  async function checkUser() {
    try {
      const currentUser = await Auth.currentAuthenticatedUser();
      setUser(currentUser);
      // If already signed in and on /callback, redirect to /
      if (window.location.pathname === '/callback') {
        history.push('/');
      }
    } catch (error) {
      setUser(null);
    }
  }

  const handleSubmit = async (e) => {
    e.preventDefault();
    console.log('Sending:', { prompt });
    try {
      const token = (await Auth.currentSession()).getIdToken().getJwtToken();
      // Update <BASE_URL> with your unique domain name
      const res = await fetch('<BASE_URL>/blend', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token
        },
        body: JSON.stringify({ prompt })
      });
      if (!res.ok) {
        const errorData = await res.json();
        console.error('Error response:', errorData);
        throw new Error(`HTTP error ${res.status}: ${JSON.stringify(errorData)}`);
      }
      const data = await res.json();
      setResponse(data);
    } catch (error) {
      console.error('Fetch error:', error);
      setResponse({ blended: `Error: ${error.message}`, grok_response: '', openai_response: '' });
    }
  };

  const signIn = () => Auth.federatedSignIn();
  const signOut = () => Auth.signOut();

  if (!user) {
    return (
      <div className="App">
        <h1>Blend AI</h1>
        <button onClick={signIn} className="blend-button">Sign In</button>
      </div>
    );
  }

  return (
    <div className="App">
      <h1>Blend AI</h1>
      <button onClick={signOut} className="signout-button">Sign Out</button>
      <form onSubmit={handleSubmit}>
        <input
          type="text"
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          placeholder="Enter your prompt"
          className="prompt-input"
        />
        <button type="submit" className="blend-button">Blend It</button>
      </form>
      {response && (
        <div className="response-container">
          <h2>Blended Response</h2>
          <p className="blended-text">{response.blended}</p>
          <div className="individual-responses">
            <div className="response-card">
              <h3>Grok Says:</h3>
              <p>{response.grok_response}</p>
            </div>
            <div className="response-card">
              <h3>OpenAI Says:</h3>
              <p>{response.openai_response}</p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;