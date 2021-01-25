# Corpshort: internal shortlink service

Yet another go/ shortlink service.

## Features

- Create, Edit, and Delete links
- Supports Redis or DynamoDB out-of-the-box
- QR Code generation for embedding on posters

## Screenshots

![screenshot of link editing page](https://img.sorah.jp/s/2018-06-19_1606_208mm.png)
![embedding PDF in Keynote](https://img.sorah.jp/s/2018-06-19_1606_l7q6g.png)


## Set up

Corpshort is a Rack application.

See [config.ru](./config.ru) for detailed configuration. The following environment variable is supported by the bundled config.ru.

- `SECRET_KEY_BASE` (required)
- `CORPSHORT_BASE_URL` (optional): Base URL to use in links (e.g. `http://go.corp.example.com`)
- `CORPSHORT_SHORT_BASE_URL` (optional): Alternative shorter base URL to present, used on texts (e.g. `http://go`)
- Backend:
  - `CORPSHORT_BACKEND` = `redis`: Use redis as a backend store
    - `REDIS_URL` (optional)
    - `CORPSHORT_REDIS_PREFIX` (optional, default: `corpshort:`)
  - `CORPSHORT_BACKEND` = `dynamodb`: Use dynamodb as a backend store
    - `CORPSHORT_DYNAMODB_REGION`
    - `CORPSHORT_DYNAMODB_TABLE`

### DynamoDB Table:

- primary key: `name`
- GSI:
  - `url-updated_at-index`:
    - primary: `url` (String)
    - sort: `updated_at` (String)
  - `updated_at_partition-updated_at-index`:
    - primary: `updated_at_partition` (String)
    - sort: `updated_at` (String)

![](https://img.sorah.jp/s/2018-06-19_1406_hxxjt.png)

## API

- All parameters are accepted in x-www-form-encoded.
- All APIs returns a JSON.

### Objects

#### Link

``` json
{
  "name": "Name",
  "url": "https://example.org",
  "updated_at": "2018-06-25T18:32:17Z",
  "show_url": "https://localhost/Name+",
  "link_url": "https://localhost/Name",
  "short_link_url": "https://go/Name"
}
```

### Endpoints

#### Recent links: GET `/+api/links`

- Parameters:
  - `token` (optional)
- Returns link names (`{links: [""], next_token: ""}`)

### Create a link: POST `/+api/links`

- takes `name` and `url`
- Returns a link.

### GET `/+api/links/*name`

- Returns a link.

### DELETE `/+api/links/*name`

- Deletes a link.

### GET `/+api/urls`

- Takes `url` parameter
- Returns link names.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sorah/corpshort.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
