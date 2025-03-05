cd ../frontend
npm install
npm run build
aws s3 sync build/ s3://blend-ai-frontend-<update_from_tofu_output> --profile <profile>
cd ..