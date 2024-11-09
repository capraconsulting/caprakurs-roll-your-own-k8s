data "aws_route53_zone" "delegated_zone" {
  provider = aws.dns
  name     = local.hosted_zone_name
}

output "zoneid" {
  value = data.aws_route53_zone.delegated_zone.zone_id
}

resource "aws_route53_record" "master_node" {
  provider = aws.dns
  name     = "${local.node_names["main"]}.${local.base_domain}"
  type     = "CNAME"
  zone_id  = data.aws_route53_zone.delegated_zone.id
  ttl = 60

  records = [aws_instance.main.public_dns]

}