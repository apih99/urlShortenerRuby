require_relative 'spec_helper'

RSpec.describe 'URL Shortener App' do
  describe 'POST /shorten' do
    it 'creates a shortened URL' do
      post '/shorten', { url: 'https://www.example.com' }.to_json, 'CONTENT_TYPE' => 'application/json'
      
      expect(last_response).to be_ok
      expect(JSON.parse(last_response.body)).to include('shortened_url', 'original_url')
    end

    it 'returns error for invalid URL' do
      post '/shorten', { url: 'not-a-url' }.to_json, 'CONTENT_TYPE' => 'application/json'
      
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)['error']).to eq('Invalid URL format')
    end

    it 'creates URL with custom code' do
      post '/shorten', { 
        url: 'https://www.example.com',
        custom_code: 'test123'
      }.to_json, 'CONTENT_TYPE' => 'application/json'
      
      expect(last_response).to be_ok
      response = JSON.parse(last_response.body)
      expect(response['shortened_url']).to include('test123')
    end

    it 'rejects invalid custom code' do
      post '/shorten', { 
        url: 'https://www.example.com',
        custom_code: 'a'  # too short
      }.to_json, 'CONTENT_TYPE' => 'application/json'
      
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)['error']).to eq('Invalid custom code format')
    end
  end

  describe 'GET /:short_code' do
    it 'redirects to original URL' do
      # First create a shortened URL
      post '/shorten', { url: 'https://www.example.com' }.to_json, 'CONTENT_TYPE' => 'application/json'
      short_code = JSON.parse(last_response.body)['shortened_url'].split('/').last
      
      # Then try to access it
      get "/#{short_code}"
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to eq('https://www.example.com')
    end

    it 'returns 404 for non-existent short code' do
      get '/nonexistent'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'DELETE /:short_code' do
    it 'deletes a shortened URL' do
      # First create a shortened URL
      post '/shorten', { url: 'https://www.example.com' }.to_json, 'CONTENT_TYPE' => 'application/json'
      short_code = JSON.parse(last_response.body)['shortened_url'].split('/').last
      
      # Then delete it
      delete "/#{short_code}"
      expect(last_response.status).to eq(200)
      
      # Verify it's deleted
      get "/#{short_code}"
      expect(last_response.status).to eq(404)
    end
  end
end 