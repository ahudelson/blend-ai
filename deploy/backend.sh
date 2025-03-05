cd backend
aws ecr get-login-password --region us-east-1 --profile <profile> | docker login --username AWS --password-stdin <AWS_Account_ID>.dkr.ecr.us-east-1.amazonaws.com
docker buildx build --platform linux/arm64 -t blend-api .
docker tag blend-api:latest <AWS_Account_ID>.dkr.ecr.us-east-1.amazonaws.com/blend-api:latest
docker push <AWS_Account_ID>.dkr.ecr.us-east-1.amazonaws.com/blend-api:latest
cd ..