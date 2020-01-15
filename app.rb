require 'sinatra'
require 'oauth2'
require 'fhir_client'
require 'jwt'

use Rack::Session::Pool

FHIR.logger.level = Logger::INFO

CLIENT_ID = 'example'
CLIENT_SECRET = 'secret'

get '/launch' do
  iss = params[:iss]
  scope = params[:scope]

  fhir_client = FHIR::Client.new(iss)
  options = fhir_client.get_oauth2_metadata_from_conformance

  session[:oauth2] = {
    :state => 'csrf-state',
    :iss => iss,
    :options => options
  }

  oauth_client = OAuth2::Client.new(CLIENT_ID, CLIENT_SECRET,
    :authorize_url => options[:authorize_url],
    :token_url => options[:token_url],
    :site => options[:site])

  redirect oauth_client.auth_code.authorize_url(
    :redirect_uri => 'http://localhost:4567/callback',
    :aud => iss,
    :scope => scope,
    :state => 'csrf-state'
  )
end

get '/callback' do
  oauth_client = OAuth2::Client.new(CLIENT_ID, CLIENT_SECRET, session[:oauth2][:options])
  result = oauth_client.auth_code.get_token(params[:code], :redirect_uri => 'http://localhost:4567/callback')

  puts "---\n"
  puts result.inspect
  puts "\n---"

  session[:oauth2][:token] = result.token
  session[:oauth2][:context] = result.params

  redirect '/dashboard'
end

get '/dashboard' do
  iss = session[:oauth2][:iss]
  token = session[:oauth2][:token]
  context = session[:oauth2][:context]

  fhir_client = FHIR::Client.new(iss)
  fhir_client.set_bearer_token(token)

  FHIR::Model.client = fhir_client
  patient = FHIR::Patient.read(context['patient'])

  output = "<textarea cols=\"50\">#{patient.to_json}</textarea>"

  search_response = fhir_client.search(FHIR::Observation, search: { parameters: { subject: context['patient'] }})
  bundle = search_response.resource
  observations = bundle.entry

  output += "<ul>"
  observations.each { |i| output += "<li>#{i.resource.code.coding.first.display}</li>" }
  output += "</ul>"

  output
end
