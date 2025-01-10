# URL Shortener Service

A simple URL shortener service built with Ruby and Sinatra.

## Features

- URL shortening with automatic code generation
- Custom short code support
- URL validation
- SQLite database for persistence
- Simple web interface
- RESTful API

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Run the application:
```bash
bundle exec rackup -p 4567
```

## API Endpoints

### Shorten URL
```bash
POST /shorten
Content-Type: application/json

{
    "url": "https://example.com/very/long/url",
    "custom_code": "my-code"  # Optional
}
```

Custom code requirements:
- 4-10 characters long
- Only letters, numbers, underscores, and hyphens allowed
- Must be unique

### Redirect to Original URL
```bash
GET /{short_code}
```

### Get URL Info
```bash
GET /info/{short_code}
```

### Delete Shortened URL
```bash
DELETE /{short_code}
```

## Example Usage

To shorten a URL with automatic code generation:
```bash
curl -X POST http://localhost:4567/shorten \
     -H "Content-Type: application/json" \
     -d '{"url":"https://example.com/very/long/url"}'
```

To shorten a URL with a custom code:
```bash
curl -X POST http://localhost:4567/shorten \
     -H "Content-Type: application/json" \
     -d '{"url":"https://example.com/very/long/url", "custom_code":"my-link"}'
```

To access the original URL, simply open the shortened URL in a browser or use:
```bash
curl -L http://localhost:4567/{short_code}
```

To get information about a shortened URL:
```bash
curl http://localhost:4567/info/{short_code}
```

To delete a shortened URL:
```bash
curl -X DELETE http://localhost:4567/{short_code}
``` 