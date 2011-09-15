#include "imu_comm.h"

struct imu * imu_comm_init(void){
    struct imu * imu;
    imu = (struct imu *)malloc(sizeof(struct imu));
    if(imu == NULL){
	fprintf(stderr,"Failed to allocate mem. \n");
	return imu;
    }
    // Set default values
    imu->frames_sampled = 0;
    imu->unread_data = 0;
    imu->settings.fs = IMU_DEFAULT_FS;
    imu->settings.T = IMU_DEFAULT_T;
    imu->settings.gyro_sens = IMU_DEFAULT_GYRO_SENS;
    imu->settings.frame_width_bytes = IMU_DEFAULT_FS;
    return imu;
}

int imu_comm_connect(struct imu * imu, char * device){
    imu->device = fopen(device,"rb");
    if(imu->device == NULL){
	fprintf(stderr,"Device %s not found.\n",device);
	return ERROR_OPEN;
    }
    return ERROR_OK;
}

int imu_comm_disconnect(struct imu * imu){
    int retval = ERROR_OK;
    retval = fclose(imu->device);
    if(retval != ERROR_OK){
	fprintf(stderr,"Failed to close connection to device.\n");
	return ERROR_CLOSE;
    }
    imu->device = NULL;
    return ERROR_OK;
}

int imu_comm_deinit(struct imu * imu){
    int retval = ERROR_OK;
    if(imu->device != NULL)
	retval = imu_comm_disconnect(imu);
    // ignore answer and keep dying, leftovers are not reliable
    free(imu);
    return retval;
}

static double grad2rad(double degrees){
    // PI/180 == 0.017453292519943295
    return degrees*0.017453292519943295;
}

static double rad2grad(double radians){
    // 180/PI == 57.29577951308232
    return radians*57.29577951308232;
}

static int gyro_scale_adjust(struct imu * imu, double * gyro_reading){
    //TODO Implement scale calibration,
    // Note: Should be /300, but /450 seems to work better.
    // Will be sensor specific
    // Should get a true calibration instead of this.
    *gyro_reading *= 0.92955;
    return ERROR_OK;
}

static int acc_scale_adjust(struct imu * imu, double * acc_reading){
    //TODO Implement scale calibration,
    // Will be sensor specific
    // Should get a true calibration instead of this.
    return ERROR_OK;
}

static double imu_sens_g[IMU_SENS_OPT_COUNT] = {1.5, 2, 4, 6};
static int imu_sens_mv_per_g[IMU_SENS_OPT_COUNT] = {800,600,400,300};
int imu_get_sens(int sens){
    if(!(sens<IMU_SENS_OPT_COUNT))
	return ERROR_FAIL;
    return imu_sens_mv_per_g[sens];
}

static unsigned short int swap_LSB_MSB_16(unsigned short int a){
    return (((a&0xFF)<<8)|(a>>8));
}

static int imu_comm_avg(struct imu * imu){
    int tmp,i,j;
    for(i=0;i<IMU_SENSOR_COUNT;++i){// loop sensors
	tmp = 0;
	for(j=0;j<IMU_FRAME_SAMPLE_AVG_COUNT;++j)// loop sensor data
	    tmp += (int)imu->frame_buffer[j].raw[i];
	tmp /= IMU_FRAME_SAMPLE_AVG_COUNT;
	imu->avg.xyzrpy[i] = (double)tmp;
    }
    imu->avg_ready = 1;
    return ERROR_OK;
}

/** 
 * Reads data until a frame init char is found.
 * Keeps going until a end char is found. Then stops.
 * 
 * @param imu 
 * @param frame New frame is returned here.
 * 
 * @return error code
 */
static int imu_read_frame(struct imu * imu){
    int retval = ERROR_OK,watchdog,read,i;
    unsigned char tmp = '@';// Anything diff from IMU_FRAME_INIT_CHAR
    struct imu_frame * new_frame;
    new_frame = imu->frame_buffer+imu->frames_sampled;
    watchdog = 0;
    while(watchdog < IMU_DEFAULT_FRAME_SIZE_BYTES){
	retval = fread(&tmp,IMU_INIT_END_SIZE,1,imu->device);
	if(retval == 0){
	    perror("Read error...");
	    return ERROR_READ_TIMEOUT;
	}else{
	    if(tmp == IMU_FRAME_INIT_CHAR)
		break;
	}
	++watchdog;
    }
    if(watchdog>=IMU_DEFAULT_FRAME_SIZE_BYTES)
	return ERROR_READ_SYNC;

    // At this point we should be ready to read the frame, init char already read

    // Get count
    watchdog = 0;
    while(watchdog < READ_RETRIES){
	retval = fread(& new_frame->count,IMU_BYTES_COUNT,1,imu->device);
	if(retval == 0){
	    perror("Read error...");
	    return ERROR_READ_TIMEOUT;
	}else{
	    break;
	}
	++watchdog;
    }
    if(watchdog>=READ_RETRIES)
	return ERROR_READ_TIMEOUT;
  
    // Generate timestamp
    gettimeofday(& new_frame->timestamp,NULL);

    // Read sensors RAW data
    watchdog = 0;
    read = 0;
    while(watchdog < READ_RETRIES){
	retval = fread(new_frame->raw + read,IMU_BYTES_PER_SENSOR,IMU_SENSOR_COUNT,imu->device);
	if(retval == 0){
	    perror("Read error...");
	    return ERROR_READ_TIMEOUT;
	}else{
	    read += retval;
	    if(read == IMU_SENSOR_COUNT)
		// done reading
		break;
	}
	++watchdog;
    }
    if(watchdog>=READ_RETRIES)
	return ERROR_READ_TIMEOUT;
    // Change LSB/MSB
    for(i=0;i<IMU_SENSOR_COUNT;++i)
	new_frame->raw[i] = swap_LSB_MSB_16(new_frame->raw[i]);

    // Now read out the end char
    watchdog = 0;
    while(watchdog < READ_RETRIES){
	retval = fread(&tmp,IMU_INIT_END_SIZE,1,imu->device);
	if(retval == 0){
	    perror("Read error...");
	    return ERROR_READ_TIMEOUT;
	}else{
	    if(tmp == IMU_FRAME_END_CHAR)
		break;
	    else
		return ERROR_READ_SYNC;
	}
	++watchdog;
    }
    if(watchdog>=READ_RETRIES)
	return ERROR_READ_TIMEOUT;


    // Everything went ok, pat pat :)
    imu->frames_sampled += 1;
    imu->unread_data += 1;

    // If we have enough samples then update avg
    if(imu->unread_data == IMU_FRAME_SAMPLE_AVG_COUNT)
	retval = imu_comm_avg(imu);

    return ERROR_OK;
}

/**
 * Convert data read from gyro to rad/s
 * 
 * Gyro outputs ~1.65v for 0deg/sec, then this goes through a
 * 10bit ADC on the Atmega which compares 0-3.3v.
 * The data received is the result of the ADC.
 * 
 * @param imu 
 * @param frame Contains RAW data from IMU
 * @param gyro_reading Rate in rad/sec
 * 
 * @return error code
 */
static int imu_gyro_read(struct imu * imu, struct imu_frame * frame, double * gyro_reading){
    int retval = ERROR_OK, i;
    for(i = 0; i<IMU_GYROS; ++i){
	gyro_reading[i] = ((double) *(frame->raw + IMU_ACCS + i)) - imu->null_estimates.xyzrpy[IMU_ACCS + i];
	gyro_reading[i] = grad2rad(gyro_reading[i]);
	retval = gyro_scale_adjust(imu,gyro_reading+i);
	err_propagate(retval);
    }
    return retval;
}

/** 
 * 
 * 
 * @param imu 
 * @param frame Raw data from IMU
 * @param acc_reading Acceleration, in m/s^2
 * 
 * @return error code
 */
static int imu_acc_read(struct imu * imu, struct imu_frame * frame, double * acc_reading){
    int retval = ERROR_OK, i;
    for(i = 0; i<IMU_ACCS; ++i){
	// Avoid math on char to be able to hanlde negative results
	acc_reading[i] = ((double) * (frame->raw + i)) - imu->null_estimates.xyzrpy[i];
	acc_reading[i] = grad2rad(acc_reading[i]);
	retval = acc_scale_adjust(imu,acc_reading+i);
	err_propagate(retval);
    }
    return retval;
}

/** 
 * Calculates value of the sensor reading from the RAW data, using current imu calibration.
 * 
 * @param imu Current imu status
 * @param xyzrpy Answer is returned here
 * 
 * @return error code
 */
static int imu_get_latest_values(struct imu * imu, double * xyzrpy){
    int retval = ERROR_OK;
    while(imu->unread_data <= 0){
	retval = imu_read_frame(imu);
	err_propagate(retval);
    }

    struct imu_frame * frame = imu->frame_buffer + imu->frames_sampled;

    // Get ACC readings
    retval = imu_acc_read(imu, frame, xyzrpy);
    err_propagate(retval);

    // Get gyro reading
    retval = imu_gyro_read(imu, frame, xyzrpy);
    err_propagate(retval);

    imu->unread_data -= 1;
    return retval;
}

int imu_comm_get_avg(struct imu * imu, double * xyzrpy){
    if(imu->avg_ready){
	xyzrpy = imu->avg.xyzrpy;
	imu->avg_ready = 0;
	return ERROR_OK;
    }
    err_check(ERROR_AVG_NOT_ENOUGH,"Not enough samples to average");
}

int imu_comm_get_data(struct imu * imu, double * xyzrpy){
    int retval = ERROR_OK;
    retval = imu_get_latest_values(imu, xyzrpy);
    return retval;
}
