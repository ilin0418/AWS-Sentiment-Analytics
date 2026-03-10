## News Article Sentiment Analysis

The News Article Sentiment Analysis system is an application designed to take a topic and give a general sense of the sentiment of it in most mainstream news. To do this, it will search for as many relevant articles as it can find (with support for non-English languages) and using machine learning will determine their sentiment about the topic. The system will then return the number of relevant articles that are either positive, negative, or neutral. The full breakdown of the sentiment is shown in both the application frontend and an email certificate.

## Steps to run the project
### 1. Clone the git repository
`git clone https://github.com/ilin0418/AWS-Sentiment-Analytics.git`

### 2. Run the terraform
* `cd NewsSearch`
* Run `terraform init` to initialize Terraform.
* Run `terraform plan` to see the execution plan.
* Run `terraform apply` to apply the changes and provision the infrastructure.

### 3. To run the frontend URL:
#### Running on Amplify
* Open AWS Amplify
* Run Build & wait for the build and deploy
* Once it is deployed, Using the link navigate to the website
  
#### Running on the local host
* To run the frontend URL navigate to the 'amplify' directory.
* w.r.t root directory type `cd amplify`
* Run `npm install` to install dependencies
* Run `npm start` to start the development server

### 4. Once the UI is loaded:
  * Enter your query and language
  * Click 'submit'
  * Results will be displayed in the panel and also sent in an email certificate

### 5. To tear down or destroy infrastructure navigate to the 'terraforms' directory
  * Run `terraform destroy`
