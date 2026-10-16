# 3rd party
import click

# betanin
import betanin.config.betanin as conf_betanin


@click.command()
@click.password_option(help="the password to hash (prompted for if omitted)")
def main(password):
    "prints a hash of PASSWORD to put in config.toml as [frontend] password"
    click.echo(conf_betanin.hash_password(password))


if __name__ == "__main__":
    main()
