#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

export CLUSTER_CONFIG_BUCKET="odd-demo-2-clusterconfigbucket-1fnsbr3lncrub"

aws s3 cp pcluster_head_node.sh s3://$CLUSTER_CONFIG_BUCKET/pcluster_head_node.sh
aws s3 cp pcluster_head_node.sh s3://$CLUSTER_CONFIG_BUCKET/pcluster_head_node-devcluster.sh
aws s3 cp pcluster_worker_node.sh s3://$CLUSTER_CONFIG_BUCKET/pcluster_worker_node.sh
aws s3 cp pcluster_worker_node_desktop.sh s3://$CLUSTER_CONFIG_BUCKET/pcluster_worker_node_desktop.sh
