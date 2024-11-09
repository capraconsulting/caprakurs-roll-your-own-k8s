data "aws_route53_zone" "delegated_zone" {
  provider = aws.dns
  name     = local.hosted_zone_name
}

output "zoneid" {
  value = data.aws_route53_zone.delegated_zone.zone_id
}

resource "aws_route53_record" "node" {
  for_each = aws_instance.nodes
  provider = aws.dns
  name     = "node${each.key}.${local.base_domain}"
  type     = "CNAME"
  ttl      = 60
  zone_id  = data.aws_route53_zone.delegated_zone.id

  records = [each.value.public_dns]
}