
SANGFOR_ROOT=/usr/share/sangfor
export VPN_ROOT VPN_RESOURCES VPN_BIN VPN_CONF VPN_TUN FORCE_OPEN_PORTS VPN_UI VPN_PROGS
VPN_ROOT=$SANGFOR_ROOT/EasyConnect
VPN_RESOURCES=$VPN_ROOT/resources
VPN_BIN=$VPN_RESOURCES/bin
VPN_CONF=$VPN_RESOURCES/conf
VPN_TUN=tun0
VPN_PROCS="CSClient svpnservice ECAgent"
FORCE_OPEN_PORTS=54530
vpn_daemon() {
	rm -f "$VPN_CONF/ECDomainFile"

	# 在 EasyConnect 前端启动过程中，会出现 cms client connect failed 的报错，此时应该启动 sslservice.sh。但这个脚本启动得太早也会没有作用。
	# (来自 https://blog.51cto.com/13226459/2476193 的线索，感谢文章作者)
	# 进一步研究发现此时应启动 svpnservice 和 CSClient 两个程序
	{
		fake-hwaddr-run $VPN_BIN/ECAgent
		kill $!
	} > >(
			grep "\\[Register\\]cms client connect failed|ECDomainFile domain socket connect failed" -Em 1 --line-buffered
			killall -9 svpnservice CSClient
			# 在某些性能不佳的设备上（尤其是如果使用了 qemu-user 来模拟运行其他架构的 EasyConnect），CSClient 和 svpnservice 启动较慢，
			# 此时有可能 CSClient 启动完成前 ECAgent 就会等待超时、登录失败，因此启动 CSClient 前先将 ECAgent 休眠（发送 STOP 信号），
			# CSClient 启动完成（以 fifo 文件 ECDomainFile 存在为标志）后再解除 ECAgent 休眠（发送 CONT 信号）
			killall -STOP ECAgent
			fake-hwaddr-run "$VPN_BIN/svpnservice" -h "$VPN_SOURCES" &
			fake-hwaddr-run "$VPN_BIN/CSClient" &
			wait
			until [ -e "$VPN_CONF/ECDomainFile" ]; do
				sleep 0.1
			done
			killall -CONT ECAgent
			exec cat >/dev/null
		) &
}

VPN_UI=$VPN_BIN/easyconn
vpn_ui() {
	if ! output=$("$VPN_UI" login -t autologin); then
		echo "login failed"
		return 1
	fi
	if [[ ${output} == *"login successfull"* ]]; then
		while true; do
			sleep 60
		done
	fi

    if [[ ${output} == *"auto login is disabled"* ]]; then
        output=$(${VPN_UI} login ${CLI_OPTS})
        if [[ ${output} == *"login successfull"* ]]; then
            echo "login success: ${output}"
            while true; do
                sleep 60
            done
        fi
    fi

	echo "login error: ${output}"
	return 1
}
