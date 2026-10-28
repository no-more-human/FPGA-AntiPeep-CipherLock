在本地建立 known_faces/人员名称/*.jpg，建议每人 10~20 张清晰正脸。
使用 python tools/enroll_face.py --name owner 采集。照片默认不加入 Git。
授权人脸识别使用 LBPH 距离阈值，缺少活体检测，不能保证抗照片攻击。
