# Blend AI App

Blend AI is a web application that aggregates responses from xAI's Grok and OpenAI's GPT-3.5-turbo APIs to provide blended answers to user prompts. It features a React frontend hosted on Amazon S3 and CloudFront, a FastAPI backend on AWS Lambda with API Gateway, and Amazon Cognito for user authentication.

This repository is a public, sanitized version of the original project. You’ll need your own AWS account, API keys, and domain to deploy it.

---

## Features
- **Frontend:** React app with Cognito login, served via CloudFront and S3.
- **Backend:** FastAPI on Lambda, blending Grok and OpenAI responses.
- **Authentication:** Cognito User Pool with OAuth 2.0 flow.
- **Deployment:** Fully managed with OpenTofu (Terraform alternative).

---

## Prerequisites
Before you begin, ensure you have:
- **AWS Account:** Active with permissions to create Cognito, Lambda, API Gateway, S3, CloudFront, Route 53, and ACM resources.
- **Domain Name:** Registered in Route 53 (e.g., `yourdomain.com`).
- **API Keys:**
  - xAI Grok API key (from xAI developer portal).
  - OpenAI API key (from OpenAI dashboard).
- **Tools:**
  - [Node.js](https://nodejs.org/) (v14+ recommended for React 17).
  - [npm](https://www.npmjs.com/) (installed with Node.js).
  - [Docker](https://www.docker.com/) (for building Lambda image).
  - [OpenTofu](https://opentofu.org/) (v1.6+ as Terraform replacement).
  - [AWS CLI](https://aws.amazon.com/cli/) (configured with `aws configure --profile yourprofile`).

---

## Project Structure
- `frontend/`: React app source code.
- `backend/`: FastAPI backend source code.
- `terraform/`: OpenTofu configuration for AWS infrastructure.

---

## Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/blend-ai-app.git
cd blend-ai-app
```

### 2. Configure AWS Credentials
- Set up your AWS CLI profile:
```bash
aws configure --profile yourprofile
```
- Enter your AWS Access Key ID, Secret Access Key, and region (us-east-1).

### 3. Set Up API Keys and Domain
- Create a terraform/terraform.tfvars file, and replace placeholders with your values.
- You will also need to update all the placeholders in the main.
```bash
domain_name     = "blend.yourdomain.com"  # Subdomain for frontend
root_domain     = "yourdomain.com"        # Your Route 53 hosted zone
grok_api_key    = "your-xai-api-key"      # xAI Grok API key
openai_api_key  = "your-openai-api-key"   # OpenAI API key
```

### 4. Deploy Backend
#### Prerequisites:
- You must manually create an ECR Reporitory before deploying the backend to AWS
#### Instructions:
- Build Lambda Docker Image:
- Note: Replace <your-aws-account-id> with your 12-digit AWS account ID.
```bash
cd backend
aws ecr get-login-password --region us-east-1 --profile yourprofile | docker login --username AWS --password-stdin <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com
docker buildx build --platform linux/arm64 -t blend-api .
docker tag blend-api:latest <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/blend-api:latest
docker push <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/blend-api:latest
```

### 5. Deploy Infrastructure:
```bash
cd ../terraform
tofu init
tofu plan
tofu apply --auto-approve
```
- This creates Cognito, Lambda, API Gateway, S3, CloudFront, and Route 53 resources.

- Capture Outputs:
```bash
tofu output
```
- Note cognito_user_pool_id, cognito_client_id, cognito_domain, and s3_bucket_name.

### 6. Deploy Frontend
- Install Dependencies:
```bash
cd ../frontend
npm install
```
- Update Amplify Config:
- Edit `frontend/src/index.js`, `frontend/src/index.js`, and `backend/main.py`
- Replace <BASE_URL> placeholders with tofu output values.
```bash
Amplify.configure({
  Auth: {
    region: 'us-east-1',
    userPoolId: '<cognito_user_pool_id>',
    userPoolWebClientId: '<cognito_client_id>',
    mandatorySignIn: true,
    oauth: {
      domain: '<cognito_domain>',  // e.g., blend-auth-xyz.auth.us-east-1.amazoncognito.com
      scope: ['email', 'openid', 'profile'],
      redirectSignIn: 'https://blend.yourdomain.com/callback',
      redirectSignOut: 'https://blend.yourdomain.com/logout',
      responseType: 'code'
    }
  }
});
```
#### Build and Deploy:
- Replace <s3_bucket_name> and <cloudfront_distribution_id> with tofu output values.
```bash
npm run build
aws s3 sync build/ s3://<s3_bucket_name> --profile yourprofile
aws cloudfront create-invalidation --distribution-id <cloudfront_distribution_id> --paths "/*" --profile yourprofile
```
### 7. Testing the App
#### Create a Cognito Test User
In AWS Console:
- Go to Cognito > User Pools > blend-user-pool > Users.
- Create a user (e.g., email: test@example.com, temporary password: Test1234!).
- Verify via email or set a permanent password admin-side.
#### Test the App
- Visit https://blend.yourdomain.com.
- Click “Sign In,” log in with your test user.
- Enter a prompt (e.g., “why do cats purr?”) and click “Blend It.”
- Expect a blended response from Grok and OpenAI.
## Troubleshooting
- CORS Errors: Check Lambda logs (aws logs tail /aws/lambda/blend-api --profile yourprofile) and ensure main.py CORS headers match your domain.
- Login Issues: Verify Cognito callback URL (https://blend.yourdomain.com/callback) in AWS Console matches redirectSignIn.
- Deployment Fails: Run tofu apply with --debug and check error details.
## Costs
- With <10 queries/day (~300/month):

- Free Tier: Lambda, API Gateway, S3, CloudFront, Cognito, and CloudWatch costs are $0.
Route 53: $0.50/month for hosted zone.
Total: ~$0.50/month (post-Free Tier).
See AWS Cost Explorer for real-time usage.

## Contributing
- Feel free to fork, submit PRs, or open issues for improvements!