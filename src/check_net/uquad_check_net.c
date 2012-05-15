#include <uquad_check_net.h>

int uquad_check_net_server(int portno)
{
    int
	sockfd = -1,
	newsockfd = -1,
	n;
    char
	buff_o[CHECK_NET_MSG_LEN] = CHECK_NET_ACK,
	buff_i[CHECK_NET_MSG_LEN];
    struct sockaddr_in servaddr, cliaddr;
    socklen_t len;

    sockfd=socket(AF_INET,SOCK_DGRAM,0);

    bzero(&servaddr,sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr=htonl(INADDR_ANY);
    servaddr.sin_port=htons(portno);
    if(bind(sockfd,(struct sockaddr *)&servaddr,sizeof(servaddr)) < 0)
    {
	err_log_stderr("bind()");
	cleanup_if(ERROR_FAIL);
    }

    while(1)
    {
	len = sizeof(cliaddr);
	n = recvfrom(sockfd,buff_i,CHECK_NET_MSG_LEN,0,(struct sockaddr *)&cliaddr,&len);
	if (n < 0)
	{
	    /// Something went wrong, die.
	    err_log_stderr("recvfrom()");
	    cleanup_if(ERROR_IO);
	}
	if(n == CHECK_NET_MSG_LEN &&
	   (memcmp(buff_i,CHECK_NET_PING,CHECK_NET_MSG_LEN) == 0))
	{
	    /// Got msg from client, ack to inform we're alive
#ifdef DEBUG_CHECK_NET
	    err_log("server(): ping received!");
#endif
	    n = sendto(sockfd,buff_o,CHECK_NET_MSG_LEN,
		       0,(struct sockaddr *)&cliaddr,sizeof(cliaddr));
	    if (n < 0)
	    {
		err_log_stderr("sendto()");
		cleanup_if(ERROR_IO);
	    }
	    /**
	     * Client pings at a CHECK_NET_MSG_T_MS rate.
	     * We'll read more often, since timing is not
	     * a problem on the server side (PC)
	     */
	    sleep_ms(CHECK_NET_MSG_T_MS >> 1);
	}
	/// nothing new...
	usleep(100);
	continue;
    }
    cleanup:
    if(newsockfd > 0)
	close(newsockfd);
    if(sockfd > 0)
	close(sockfd);
    /// server should never die, any reason is an error
    return ERROR_FAIL;
}

int uquad_check_net_client(const char *hostIP, int portno)
{
    int
	n,
	retval,
	sockfd = -1,
	kill_retries = 0;
    uquad_bool_t
	read_ok = false,
	server_ok = false;
    struct sockaddr_in
	servaddr;
    struct hostent
	*server;
    struct timeval
	tv_out,
	tv_sent,
	tv_diff,
	tv_tmp;
    socklen_t
	len;
    char
	buff_i[CHECK_NET_MSG_LEN],
	buff_o[CHECK_NET_MSG_LEN] = CHECK_NET_PING;

    tv_out.tv_usec = 0;
    tv_out.tv_sec  = CHECK_NET_TO_S;

    server = gethostbyname(hostIP);
    if(server == NULL)
    {
	err_log_str("ERROR, no such host", hostIP);
	cleanup_if(ERROR_FAIL);
    }

    sockfd=socket(AF_INET,SOCK_DGRAM,0);

    bzero(&servaddr,sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr=inet_addr(hostIP);
    servaddr.sin_port=htons(portno);

    bzero(buff_i,CHECK_NET_MSG_LEN);
    while(1)
    {
	/// ping server
	n = sendto(sockfd,buff_o,CHECK_NET_MSG_LEN,0,
		   (struct sockaddr *)&servaddr,sizeof(servaddr));
	if (n < 0)
	{
	    err_log_stderr("sendto()");
	    goto kill_motors;
	}
	bzero(buff_i,CHECK_NET_MSG_LEN);
	gettimeofday(&tv_sent, NULL);
	/// give server some time to answer
	sleep_ms(CHECK_NET_RETRY_MS);

	/// wait for ack
	while(1)
	{
	    len = sizeof(servaddr);
	    retval = check_io_locks(sockfd, NULL, &read_ok, NULL);
	    cleanup_if(retval);
	    if(read_ok)
	    {
		n=recvfrom(sockfd,buff_i,CHECK_NET_MSG_LEN,
			   0,(struct sockaddr *)&servaddr,&len);
		if (n < 0)
		{
		    err_log_stderr("recvfrom()");
		    goto kill_motors;
		}
		if (n == CHECK_NET_MSG_LEN &&
		    (memcmp(buff_i,CHECK_NET_ACK,CHECK_NET_MSG_LEN) == 0))
		{
		    // ack received
#ifdef DEBUG_CHECK_NET
	    err_log("client(): ack received!");
#endif
		    server_ok = true;
		    sleep_ms(CHECK_NET_MSG_T_MS);
		    break;
		}
		sleep_ms(CHECK_NET_RETRY_MS);
	    }

	    /// check timeout
	    gettimeofday(&tv_tmp, NULL);
	    (void) uquad_timeval_substract(&tv_diff, tv_tmp, tv_sent);
	    retval = uquad_timeval_substract(&tv_diff, tv_out, tv_diff);
	    if(retval < 0)
	    {
		/// timed out, game over
		kill_motors:
		if(kill_retries == 0)
		{
		    if(!server_ok)
		    {
			err_log("");
			err_log("");
			err_log("");
			err_log("");
			err_log("");
			err_log("-- -- -- -- --");
			err_log("-- -- -- -- -- -- -- -- -- --");
			err_log("WARN: Will NOT run checknet, server never acked...");
			err_log("-- -- -- -- -- -- -- -- -- --");
			err_log("-- -- -- -- --");
			err_log("");
			err_log("");
			err_log("");
			err_log("");
			err_log("");
			goto cleanup;
		    }
		    err_log("check_net: Connection lost! Killing motors...");
		}
		retval = system(KILL_MOTOR_CMD);
		if(retval < 0 && kill_retries++ < CHECK_NET_KILL_RETRIES)
		{
		    usleep(1000);
		    goto kill_motors;
		}
		goto cleanup;
	    }
	}
    }
    cleanup:
    if(sockfd > 0)
	close(sockfd);
    /// Client should never die, any reason is an error
    return ERROR_FAIL;
}
