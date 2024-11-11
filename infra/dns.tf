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

resource "aws_dynamodb_table_item" "dns_records" {
  count = var.persist_dns_records_to_dynamo ? 1 : 0

  depends_on = [aws_route53_record.node]
  hash_key   = "username"
  item       = jsonencode(
    {
      "username" : { "S" : data.aws_canonical_user_id.current_user.display_name },
      "records" : { "SS" : [for record in aws_route53_record.node : record.fqdn] }
    })
  table_name = "k8s-kurs-group-management-dashboard"
}